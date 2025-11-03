# create the feature engineering pipeline

import pandas as pd
import numpy as np
import datetime
import matplotlib.pyplot as plt
import logging
import pickle
from numpy import sqrt, argmax
from typing import List, Any
from sklearn.inspection import permutation_importance
from sklearn.linear_model import LogisticRegression
from sklearn.ensemble import GradientBoostingClassifier
from sklearn.model_selection import RandomizedSearchCV, train_test_split, StratifiedKFold
# New Imports for comprehensive evaluation metrics
from sklearn.metrics import precision_score, recall_score, f1_score, roc_auc_score, confusion_matrix, ConfusionMatrixDisplay, auc, roc_curve, precision_recall_curve
from sklearn.preprocessing import StandardScaler, OneHotEncoder, FunctionTransformer
from sklearn.compose import ColumnTransformer
from sklearn.impute import SimpleImputer
from imblearn.pipeline import Pipeline as ImbPipeline
from imblearn.combine import SMOTETomek

from utils import safe_log_transform, calculate_binary_metrics
from preprocessing import DataPreprocessing


EXPERIMENT_ID = 0

class ModelBuild:

    def __init__(self, preprocessed_data:pd.DataFrame, target_col:str, ID_col: str, log_features: List[str] = None, model_type: str = 'GBC',
                 splits: int = 5):
        self.data = preprocessed_data
        self.target_col = target_col
        self.ID_col = ID_col
        self.log_features = log_features if log_features is not None else []
        self.model_type = model_type.upper()

        self.timestamp = None

        self.X_train = None
        self.X_test = None
        self.y_train = None
        self.y_test = None
        self.ID_test = None # this can be used for the model QA
        #self.ID_train = None
        self.best_estimator = None
        self.splits = splits

        if self.model_type not in ['GBC', 'LR']:
            raise ValueError("model_type must be 'GBC' for GradientBoostingClassifier or 'LR' for LogisticRegression.")

    def split_data(self):
        if self.data is None:
            logging.error("Data not loaded.")
            return None
        
        X = self.data.drop(columns=[self.target_col, self.ID_col])
        y = self.data[self.target_col]
        ID = self.data[self.ID_col]
        
        self.X_train, self.X_test, self.y_train, self.y_test = train_test_split(X, y, stratify=y, random_state=42)

        self.ID_test = ID.loc[self.X_test.index]
        #self.ID_train = ID.loc[self.X_train.index]

    def transform_data(self):
        if self.X_train is None:
            logging.error("Data must be split before fitting.")
            return
            
        all_numerical = self.X_train.select_dtypes(include=[np.number]).columns.to_list()  
        categorical_features = self.X_train.select_dtypes(include=['category', 'object']).columns.to_list()

        # ----------------------------------------------------
        # Logging Categorical Features
        logging.info(f"Categorical Features ({len(categorical_features)}): {categorical_features}")
        # ----------------------------------------------------

        binary_features = []

        for col in all_numerical:
            if set(self.X_train[col]).issubset({0,1}):
                binary_features.append(col)
        
        numerical_features = [col for col in all_numerical if col not in binary_features + self.log_features]

        # ----------------------------------------------------
        # Logging Remaining Feature Types
        logging.info(f"Numerical Features ({len(numerical_features)}): {numerical_features}")
        logging.info(f"Log-Transformed Features ({len(self.log_features)}): {self.log_features}")
        logging.info(f"Binary (0/1) Features ({len(binary_features)}): {binary_features}")
        # ----------------------------------------------------

        # Transformer Definitions
        categorical_transformer = ImbPipeline(steps=[
            ('imputer', SimpleImputer(strategy='constant', fill_value='missing_cat')),
            ('onehot', OneHotEncoder(handle_unknown='ignore'))
        ])

        numerical_transformer = ImbPipeline(steps=[
            ('imputer', SimpleImputer(strategy='constant', fill_value=-9999)),
            ('std_scaler', StandardScaler())
        ])

        binary_transformer =  ImbPipeline(steps = [
            ('imputer', SimpleImputer(strategy='constant', fill_value=0))
        ])

        log_transformer = ImbPipeline(steps=[
            ('imputer', SimpleImputer(strategy='constant', fill_value=0)),
            ('log', FunctionTransformer(safe_log_transform, feature_names_out='one-to-one')),
            ('std_scaler', StandardScaler())
        ])

        # Column Transformer (Preprocessor)
        transformers = [
            ('categorical', categorical_transformer, categorical_features)
        ]

        if numerical_features:
            transformers.append(('num', numerical_transformer, numerical_features))
        
        if binary_features:
            transformers.append(('binary', binary_transformer, binary_features))

        if self.log_features:
            transformers.append(('log', log_transformer, self.log_features))

        preprocessor = ColumnTransformer(
            transformers = transformers,
            remainder = 'drop'
        )
        
        # Model-Specific Pipeline and Grid Setup

        smote_params = {
            'smote_tomek__sampling_strategy': [0.1, 0.2, 0.3],
        }

        # Pipeline grid

        if self.model_type == 'GBC':
            # GBC Pipeline & Grid
            estimator = GradientBoostingClassifier(random_state=42, subsample=0.80, max_features='sqrt')
            pipeline = ImbPipeline(steps=[
                ('preprocessor', preprocessor),
                ('smote_tomek', SMOTETomek(random_state=42)),
                ('GBC', estimator)
            ])
            param_grid = {
                **smote_params,
                'GBC__n_estimators': [50, 100, 200],
                'GBC__max_depth': [2, 3, 4], # Regularized depth
                'GBC__min_samples_leaf': [20, 50, 100], # Regularized leaf size
                'GBC__learning_rate': [0.01, 0.1]
            }
            logging.info("Building Gradient Boosting Classifier (GBC) model.")
            
        elif self.model_type == 'LR':
            # LR Pipeline & Grid
            estimator = LogisticRegression(random_state=42, solver='saga', max_iter=5000) # Use saga for L1/L2 and large data
            pipeline = ImbPipeline(steps=[
                ('preprocessor', preprocessor),
                ('smote_tomek', SMOTETomek(random_state=42)),
                ('LR', estimator)
            ])
            param_grid = {
                **smote_params,
                'LR__C': [0.01, 0.1, 1.0, 10.0], # Inverse regularization strength
                'LR__penalty': ['l1', 'l2', 'elasticnet'],
                'LR__l1_ratio': [0.1, 0.5, 0.9] if 'elasticnet' in ['l1', 'l2', 'elasticnet'] else [None] # For elasticnet
            }
            logging.info("Building Logistic Regression (LR) model.")

        # Randomized Search
        stratified_cv = StratifiedKFold(n_splits=self.splits , shuffle=True, random_state=42)
        random_search = RandomizedSearchCV(estimator=pipeline, 
                                  param_distributions=param_grid, 
                                  n_iter=10,
                                  scoring='f1_weighted', 
                                  cv=stratified_cv, 
                                  n_jobs=-1, 
                                  random_state=42,
                                  verbose=2)
        
        random_search.fit(self.X_train, self.y_train)

        logging.info(f"Best cross-validation score: {random_search.best_score_}")
        logging.info(f"Best parameters: {random_search.best_params_}")
        
        self.best_estimator = random_search.best_estimator_

    def evaluate_model(self):
        """
        Calculates and prints avg precision, avg recall, and AUROC 
        for both the training and testing sets.
        """
        if self.best_estimator is None:
            logging.error("Model must be trained before evaluation. Run run_model_pipeline() first.")
            return

        logging.info("\n--- MODEL EVALUATION (TRAIN & TEST) ---")

        sets = {
            'Train': (self.X_train, self.y_train),
            'Test (Unseen)': (self.X_test, self.y_test)
        }

        # 2. Metric Calculation Loop: Use the imported utility function
        results = {}
        for name, (X_data, y_true) in sets.items():
            logging.info(f"Calculating metrics for {name} set...")
            results[name] = calculate_binary_metrics(
                X=X_data, 
                y_true=y_true, 
                model=self.best_estimator
            )
        
        # 3. Output Results (Adjusted to match the utility function's output keys)
        print("\n--- PERFORMANCE SUMMARY ---")
        for name, metrics in results.items():
            print(f"\n{name} Set:")
            if isinstance(metrics, dict) and "Error" not in metrics:
                # Keys are now simply 'Precision', 'Recall', 'F1', 'AUROC'
                print(f"  {'Precision':<25}: {metrics.get('Precision')}")
                print(f"  {'Recall':<25}: {metrics.get('Recall')}")
                print(f"  {'F1':<25}: {metrics.get('F1')}")
                print(f"  {'AUROC':<25}: {metrics.get('AUROC')}")
            else:
                print(f"  {metrics.get('Error', 'Calculation Failed')}")
        print("---------------------------\n")

        return results

    def save_results_json(self, results_dict: dict, filename: str = 'model_metrics.json'):
        """Saves the evaluation results dictionary to a local JSON file."""
        try:
            with open(filename, 'w') as f:
                # Use indent=4 for human-readable formatting
                json.dump(results_dict, f, indent=4)
            logging.info(f"Evaluation metrics successfully saved to {filename}")
        except Exception as e:
            logging.error(f"Failed to save JSON file: {e}")

    def save_model_artifact(self, filename: str = 'full_model_artifact.pkl'):
        """Saves the fitted model pipeline AND the test data needed for QA in one file."""
        if self.best_estimator is None or self.X_test is None:
            logging.error("Cannot save artifact: Model or test data is missing.")
            return

        # Bundle everything into a single dictionary
        full_artifact = {
            'model': self.best_estimator,
            # 'X_train': self.X_train, # Added train data for ModelQA to use if needed
            # 'y_train': self.y_train, # Added train data for ModelQA to use if needed
            'X_test': self.X_test,
            'y_test': self.y_test,
            'ID_test': self.ID_test
        }
        
        try:
            with open(filename, 'wb') as f:
                # Pickle the entire dictionary
                pickle.dump(full_artifact, f, protocol=4)
            logging.info(f"Full model artifact successfully saved to {filename}")
        except Exception as e:
            logging.error(f"Failed to save model artifact file: {e}")

    def run_model_pipeline(self):
        """
        Primary method to execute the entire modeling process: 
        splits data, fits the model, evaluates performance, and saves results/model.
        
        Returns: The best fitted model pipeline (self.best_estimator).
        """
        logging.info("--- Starting Model QA Pipeline ---")

        # Increment the class-level ID for this run
        global EXPERIMENT_ID
        EXPERIMENT_ID += 1
        self.current_experiment_id = EXPERIMENT_ID
        self.timestamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
        run_prefix = f"Exp{self.current_experiment_id:03d}_{self.timestamp}"
        logging.info(f"Current Experiment ID: {self.current_experiment_id} | Timestamp: {self.timestamp}")

        self.split_data()
        
        if self.X_train is None:
            logging.error("Pipeline aborted: Data split failed.")
            return None
        
        # FIT MODEL (Grid Search)
        self.transform_data()
        
        if self.best_estimator is None:
            logging.error("Pipeline aborted: Model fitting failed.")
            return None
        
        # EVALUATE MODEL
        logging.info("Starting model evaluation...")
        results_dict = self.evaluate_model()
        
        # SAVE RESULTS AND MODEL
        if results_dict:
            # Save evaluation metrics to JSON
            self.save_results_json(
                results_dict=results_dict, 
                filename=f'{run_prefix}_metrics.json'
            )
        
        # Save the best fitted pipeline
        self.save_model_artifact(
            filename=f'{run_prefix}_artifact.pkl'
        )
        
        logging.info("--- Model QA Pipeline Complete ---")
        
        return self.best_estimator
    
    
if __name__ == '__main__':
    # Create a dummy DataFrame with an ID column and all feature types
    # data = {'id': [101, 102, 103, 104, 105, 106, 107, 108, 109, 110],
    #         'numerical_1': [1, 2, np.nan, 4, 5, 6, 7, 8, 9, 10],
    #         'numerical_2': [10, np.nan, 30, 40, 50, 60, 70, 80, 90, 100],
    #         'highly_skewed_feature': [1, 10, 100, 1000, 10000, 100, 10, 1, 1, 10],
    #         'categorical_1': ['A', 'B', 'A', 'C', np.nan, 'A', 'B', 'A', 'C', 'C'],
    #         'categorical_2': [np.nan, 'X', 'Y', 'Z', 'Y', 'X', 'Y', 'Z', 'Y', 'X'],
    #         'binary_feature': [0, 1, np.nan, 0, 1, 0, 1, 0, 1, np.nan],
    #         'y_value': [0, 1, 0, 0, 0, 1, 0, 1, 0, 0]}
    
    # df = pd.DataFrame(data)
    
    # print("Original DataFrame:")
    # print(df)


    file_path = "/Users/aurora/Projects/MyGit/IndependentProjects/Windfall_aleport/data/raw/windfall_ds_challenge"
    data_preprocessing = DataPreprocessing(
        file_paths=[
            f"{file_path}/windfall_features.csv",
            f"{file_path}/donations.csv",
            f"{file_path}/major_donor_labels.csv",
        ]
    )

    data = data_preprocessing.run_preprocessing_pipeline().data

    # Create the transformation pipeline by explicitly passing the feature names
    log_features_list = [
    'NetWorth'
    ]

    #drop_columns = outcome_features
    model_build = ModelBuild(
                            preprocessed_data=data,#.drop(columns=drop_columns), 
                            target_col='target', 
                            ID_col='candidate_id', 
                            log_features=log_features_list, 
                            model_type='LR',
                            splits=5
                            )
    model_build.run_model_pipeline()
    print("Model run complete. Check log/files for results.")


    
            
    
    