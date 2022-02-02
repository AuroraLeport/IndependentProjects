import pandas as pd
import numpy as np

def clean_dataset(df):
    '''
    drop na
    
    Args:
        df (dataframe)
    Returns:
        a dataframe with no null values and index reset.
    ''' 
    df = df.dropna(how='any', axis=0)

    return df.reset_index(drop=True)

def create_features_df_features(df, ind_features=['totalHouseholdDebt','primaryPropertyLoanToValue','primaryPropertyValue', 'propertyCount', 'NetWorth'], ID='candidate_id'):
    '''
    create features off of df_features dataset.
    
    Args:
        df (dataframe):  df_features.csv
        ind_features (list) = ['totalHouseholdDebt', 'primaryPropertyLoanToValue','primaryPropertyValue', 'propertyCount', 'NetWorth']
        ID (str) = 'candidate_id'
    Returns:
        a dataframe with added features used for modeling.
    ''' 
    # drop na and unnecessary columns
    df = clean_dataset(df)
    df = df[[ID]+ind_features]
    
    # feature engineering
    # LTV ratio of 80% or less is ideal.
    lmdfx_idealLTV = lambda x: (1 if x <= .80 else 0)
    df['primaryPropertyLoanToValue_ideal'] = df['primaryPropertyLoanToValue'].apply(lmdfx_idealLTV)

    # what fraction of the primary property LTV is the downpayment
    # primaryPropertyValueDownpayment_ratio = 1 - primaryPropertyLoanToValue
    #lmdfx_LTVfraction = lambda x: 1 - x
    #df['primaryPropertyValueDownpayment_fraction'] = df['primaryPropertyLoanToValue'].apply(lmdfx_LTVfraction)

    # primaryPropertyValue scaled by NetWorth
    df['primaryPropertyValueToNetWorth_ratio'] = (df['primaryPropertyValue'] / df['NetWorth'])

    # LoanAmount = primaryPropertyLoanToValue * primaryPropertyValue
    df['LoanAmount'] = df['primaryPropertyLoanToValue'] * df['primaryPropertyValue']
    
    df.drop(columns=['totalHouseholdDebt','primaryPropertyLoanToValue'], axis=1, inplace=True)
    
    return df


def create_features_df_donations(df, PredictedOn='2016-08-01'):
    '''
    create features off of df_donations dataset.
    
    Args:
        df (dataframe):  df_donations.csv col = ['cand_id', 'trans_date', 'amount']
        PredictedOn (str format 'Y-m-d'): date of prediction
    Returns:
        a dataframe with features used for modeling.
    ''' 
    df = clean_dataset(df)
    
    df.set_axis(['candidate_id', 'trans_date', 'amount'], axis=1, inplace=True)
    df['trans_date'] = pd.to_datetime(df['trans_date']).copy()
    
    samedatelist = [PredictedOn for x in range(df.shape[0])] 
    df['DaysFromPrediction'] = (df['trans_date'] - pd.to_datetime(samedatelist)).dt.days
    
    # count times candidates have donated in last 1 years
    #lmbdfx = lambda x: (1 if x < 0 and x >= -360 else 0)
    #df['count_trans_date_prev360d1'] = df['DaysFromPrediction'].apply(lmbdfx)

    # count times candidates have donated in last 2 years
    lmbdfx = lambda x: (1 if x < -360 and x >= -720 else 0)
    df['count_trans_date_prev360d2'] = df['DaysFromPrediction'].apply(lmbdfx)

    # count times candidates have donated in last 3 years
    lmbdfx = lambda x: (1 if x < -720 and x >= -1080 else 0)
    df['count_trans_date_prev360d3'] = df['DaysFromPrediction'].apply(lmbdfx)

    # count times candidates have donated in last 4 years
    lmbdfx = lambda x: (1 if x < -1080 and x >= -1440 else 0)
    df['count_trans_date_prev360d4'] = df['DaysFromPrediction'].apply(lmbdfx)

    # count times candidates have donated in last 5+ years
    lmbdfx = lambda x: (1 if x < -1440 and x >= -1800 else 0)
    df['count_trans_date_prev360d5'] = df['DaysFromPrediction'].apply(lmbdfx)

    # amount spent per year prior to prediction date. 0 >= post prediction date
    #df['amount_prev360d1'] = pd.DataFrame(np.where(df['count_trans_date_prev360d1'] == 1, df['amount'], 0), columns=['amount_prev360d1'])
    df['amount_prev360d2'] = pd.DataFrame(np.where(df['count_trans_date_prev360d2'] == 1, df['amount'], 0), columns=['amount_prev360d2'])
    df['amount_prev360d3'] = pd.DataFrame(np.where(df['count_trans_date_prev360d3'] == 1, df['amount'], 0), columns=['amount_prev360d3'])
    df['amount_prev360d4'] = pd.DataFrame(np.where(df['count_trans_date_prev360d4'] == 1, df['amount'], 0), columns=['amount_prev360d4'])
    df['amount_prev360d5'] = pd.DataFrame(np.where(df['count_trans_date_prev360d5'] == 1, df['amount'], 0))

    df_addfeatures = df.groupby('candidate_id').agg(sum).iloc[:, 2:].reset_index()
    # cum prev 5 years
    df_addfeatures['count_trans_date_prev5y'] = pd.DataFrame(df_addfeatures.iloc[:,1:6].sum(axis=1), columns=['count_trans_date_prev5y'])
    #df_addfeatures['amount_prev5y'] = pd.DataFrame(df_addfeatures.iloc[:,6:11].sum(axis=1), columns=['amount_prev5y'])
    # cum prev 2 years
    #df_addfeatures['count_trans_date_prev2y'] = pd.DataFrame(df_addfeatures.iloc[:,1:3].sum(axis=1), columns=['count_trans_date_prev5y'])
    #df_addfeatures['amount_prev2y'] = pd.DataFrame(df_addfeatures.iloc[:,6:8].sum(axis=1), columns=['amount_prev5y'])
    
    df_addfeatures.drop(columns=['count_trans_date_prev360d2','count_trans_date_prev360d3','count_trans_date_prev360d4','count_trans_date_prev360d5'], axis=1, inplace=True)
    
    return df_addfeatures