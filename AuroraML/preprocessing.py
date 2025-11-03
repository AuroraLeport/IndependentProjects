# This file module contains a class for loading and preprocessing data.
import pandas as pd
import numpy as np
from datetime import date
from dateutil.relativedelta import relativedelta
from functools import reduce
import logging

# import joblib


class DataPreprocessing:
    """
    A class to handle data loading, feature engineering, and preprocessing.
    """

    # CURRENT_DATE = pd.Timestamp.now()
    CURRENT_DATE = date.today()

    def __init__(self, file_paths=[None], project_name="client_x_ptg"):
        """
        Initializes the DataPreprocessing class with a list of file paths

        Args:
            file_paths (list): A list of file paths to the datasets.
        """
        if file_paths:
            self.file_paths = file_paths
            self.project_name = project_name

        self.data = None
    
    def load_data(self):
        """
        Loads the dataset from specified file paths.

        Returns:
            tuple: A tuple containing the label, donation and feature DataFrames.
        """

        self.label_df, self.donation_df, self.feature_df = None, None, None

        try:
            data_map = {"label": (lambda df: df.rename(columns={"cand_id": "candidate_id", "ideal_donor": "target"}), "label_df"),
                        "donation": (lambda df: df.rename(columns={"cand_id": "candidate_id"}), "donation_df"),
                        "feature": (lambda df: df.rename(columns={"cand_id": "candidate_id"}), "feature_df")
            }
            
            for file_path in self.file_paths:
                key = next((k for k in data_map if k in file_path), None)
                
                if key:
                    processor, df_name =  data_map[key]
                    
                    # load the data
                    df_temp = pd.read_csv(file_path)
                    df_temp = processor(df_temp)
                    
                    if key == "label":
                        self.label_df = df_temp
                    elif key == "donation":   
                        self.donation_df = df_temp
                    elif key == "feature":
                        self.feature_df = df_temp
                    logging.info(f"Data frame {df_name} successfully loaded from {file_path}.")
                    
            return

        except Exception as e:
            logging.error(f"Error loading data: {e}")
            return None, None, None

    def engineer_features(self):
        """
        Engineers features by merging and aggregating data from loaded files.

        Returns:
            pd.DataFrame: A DataFrame with all the feature and the target variable.
        """

        if self.label_df is None or self.donation_df is None or self.feature_df is None:
            logging.info("One or more datasets are None. Cannot engineer features.")
            return None

        logging.info("Engineering features...")
        # Keep only donations linked to candidates and their target variable in the label_df
        self.donation_df = pd.merge(self.label_df, self.donation_df, on="candidate_id", how="left")

        # Define range of valid dates and limit donation dates
        self.donation_df["trans_date"] = pd.to_datetime(self.donation_df["trans_date"])
        min_year = 1950

        pred_date = DataPreprocessing.CURRENT_DATE - relativedelta(years=5)
        pred_date = pred_date.strftime("%Y-%m-%d")

        pred_date = "2016-01-01"

        self.donation_df = self.donation_df[
            (self.donation_df["trans_date"].dt.year >= min_year)
            & (self.donation_df["trans_date"] <= pred_date)
        ].copy()

        # Aggregate donations into window features
        self.donation_df["days_from_prediction"] = (
            self.donation_df["trans_date"] - pd.to_datetime(pred_date)
        ).dt.days
        bins = [-np.inf, -5 * 365, -4 * 365, -3 * 365, -2 * 365, -1 * 365, 0]
        labels = [
            "donation_historical",
            "donation_p5yr",
            "donation_p4yr",
            "donation_p3yr",
            "donation_p2yr",
            "donation_p1yr",
        ]
        self.donation_df["time_bucket"] = pd.cut(
            self.donation_df["days_from_prediction"], bins=bins, labels=labels, ordered=True
        )

        # Calculate backward cumulative sum and count features
        self.donation_df["count"] = self.donation_df["trans_date"].notna().astype(int)
        self.donation_df = self.donation_df.sort_values(
            ["candidate_id", "trans_date"], ascending=False
        ).copy()

        self.donation_df["cum_count"] = self.donation_df.groupby(["candidate_id"])[
            "count"
        ].cumsum()

        self.donation_df["cum_sum"] = self.donation_df.groupby(["candidate_id"])[
            "amount"
        ].cumsum()

        # Aggregate fixed window features and get max of cumulative features
        bucket_agg = self.donation_df.groupby(
            ["candidate_id", "time_bucket"],
            observed=True,
        ).agg(
            # count=("time_bucket", "count"),
            # total=("amount", "sum"),
            # avg=("amount", "mean"),
            cum_sum=("cum_sum", "max"),
            cum_count=("cum_count", "max"),
            #cum_average =("cum_sum", "mean")
        )

        # Pivot and Clean
        bucket_agg = bucket_agg.pivot_table(
            index="candidate_id",
            # values=["count", "total", "avg", "cum_sum", "cum_count"],
            values=["cum_sum", "cum_count"],
            columns="time_bucket",
            fill_value=0,
            observed=True,
        )

        bucket_agg.columns = [
            "_".join(col[::-1]).strip() for col in bucket_agg.columns.values
        ]
        bucket_agg.reset_index(inplace=True)

        bucket_agg.drop(
            columns=[
                "donation_p1yr_cum_sum",
                "donation_p3yr_cum_sum",
                "donation_p4yr_cum_sum",
                "donation_p1yr_cum_count",
                "donation_p3yr_cum_count",
                "donation_p4yr_cum_count",
            ],
            inplace=True,
            errors="ignore",
        )

        # Calculate Cumulative Average Features (Post-Pivot)
        cum_avg_buckets = ["donation_p2yr", "donation_p5yr", "donation_historical"]
        for bucket in cum_avg_buckets:
            cum_sum_col = f"{bucket}_cum_sum"
            cum_count_col = f"{bucket}_cum_count"
            cum_avg_col = f"{bucket}_cum_avg"

            bucket_agg[cum_avg_col] = (
                bucket_agg[cum_sum_col].div(bucket_agg[cum_count_col]).fillna(0)
            )

        # Merge donation to label features
        bucket_agg.set_index("candidate_id", inplace=True)
        self.label_df.set_index("candidate_id", inplace=True)
        self.feature_df.set_index("candidate_id", inplace=True)

        all_features = bucket_agg.join(self.feature_df, how="left")

        self.data = self.label_df[["target"]].join(all_features, how="left").reset_index()

        logging.info("Feature engineering completed.")

        return 
    
    def run_preprocessing_pipeline(self):
        
        self.load_data()

        # Check if loading failed (load_data returns None, None, None on error)
        if self.label_df is None or self.donation_df is None or self.feature_df is None:
            return None

        self.engineer_features()

        return self


if __name__ == "__main__":
    file_path = "/Users/aurora/Projects/MyGit/IndependentProjects/Windfall_aleport/data/raw/windfall_ds_challenge"
    data_preprocessing = DataPreprocessing(
        file_paths=[
            f"{file_path}/windfall_features.csv",
            f"{file_path}/donations.csv",
            f"{file_path}/major_donor_labels.csv",
        ]
    )

    full_df = data_preprocessing.run_preprocessing_pipeline().data
    print(full_df.head())
    
    columns = [
        "candidate_id",
        "donation_historical_cum_count",
        "donation_historical_cum_sum",
        "donation_historical_cum_avg",
    ]
    print(
        full_df[full_df["candidate_id"].isin(["candidate_0", "candidate_1"])][
            columns
        ].head()
    )

    print(full_df.columns)