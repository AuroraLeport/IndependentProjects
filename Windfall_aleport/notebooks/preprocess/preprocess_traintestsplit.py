# preprocess_traintestsplit.py
#------------------------------------------------------------------------------ 
# import packages
#------------------------------------------------------------------------------
import numpy as np
import pandas as pd
from sklearn.model_selection import train_test_split
from sklearn.model_selection import StratifiedKFold

"""
feature_target_split(): function that seperates the target variable(s) from feature variables. Prints metadata about the full dataset.
train_test_stratifysplit(): function that uses sklearn's train_test_split() to create stratified splits at a default of test size = 0.30 and random state kept constant. 
"""

def feature_target_split(df, cnames_to_drop=['ideal_donor', 'candidate_id'], target_col='ideal_donor'):
    '''
    Args:
        df (DataFrame): data to be analyzed
        cnames_to_drop (list): list of names to be dropped from df
        target_col (str): name of column of true values. 
    Returns:
        DataFrame of X values
        Series of y values
    ''' 
    # get feature names
    fset=[x for x in df if x not in cnames_to_drop]
    
    # Breaking up preprocessed data into predictor and target
    X=df[fset]
    y=df[target_col]
    
    print('Metadata about full dataset:')
    print('    number of members in full dataset: %d' % len(X))
    print('    number of features in full dataset = %d' % len(fset))
    print('    number of classes in full dataset : %d \n' %y.nunique())
    print('')
    
    return X, y


def train_test_stratifysplit(df, cnames_to_drop, target_col, test_size=0.3, random_state=42):
    '''
    If the argument `test_size` isnt't passed in, the default 0.30 is used.
    If the argument `random_state` isnt't passed in, the default 0.30 is used.
    
    Args:
        df (DataFrame): data to be analyzed
        cnames_to_drop (list): list of names to be dropped from df
        target_col (str): name of column of true values. 
        test_size (float): should be between 0.0 and 1.0 and represent the proportion of the dataset to include in the test split.
        random_state (float): Controls the shuffling applied to the data before applying the split. Pass an int for reproducible output across multiple function calls.
    Returns:
        DataFrame of Xtrain and Xtest values
        Series of ytrain and y test values
    ''' 
    # split into train/test using stratification
    X, y = feature_target_split(df, cnames_to_drop=cnames_to_drop, target_col=target_col)
    Xtrain, Xtest, ytrain, ytest = train_test_split(X, y, test_size=test_size, stratify=y, random_state=random_state)

    print('Metadata about train and test features:')
    print('    size of training feature (Xtr): %d x %d' % (Xtrain.shape[0], Xtrain.shape[1]))    
    print('    size of test feature (Xte)    : %d x %d' % (Xtest.shape[0], Xtest.shape[1]))
    print('')

    # target to predict
    print('Metadata about target:')
    print('    size of training target (ytr) : %d' % (ytrain.shape[0]))
    print('    size of test target (yte)     : %d' % (ytest.shape[0]))
    print('    training target: neg/pos = %.2f' % ((ytrain.shape[0]-ytrain.sum()) * 1.0 / ytrain.sum()))
    print('    test target    : neg/pos = %.2f' % ((ytest.shape[0]-ytest.sum()) * 1.0 / ytest.sum()))
    print('')

    # size and proportion of positive and negative class
    print('SIZE full dataset: positive class = (%d); negative class = (%d)' %(df[target_col].value_counts()[1],df[target_col].value_counts()[0]))
    print('PROPORTION full dataset: positive class = (%.3f); negative class = (%.3f) \n' %(df[target_col].value_counts()[1]/df.shape[0], df[target_col].value_counts()[0]/df.shape[0]))
    
    # check: proportion of positive to negative same in train, test and all
    print('SIZE train: positive class = (%d); negative class = (%d)' %(ytrain.value_counts()[1],ytrain.value_counts()[0]))
    print('PROPORTION train: train positive (%.3f); train negative (%.3f) class' %(ytrain.value_counts()[1]/ytrain.shape[0], ytrain.value_counts()[0]/ytrain.shape[0]))
    print('')
    print('SIZE test: positive class = (%d); negative class = (%d)' %(ytest.value_counts()[1],ytest.value_counts()[0]))
    print('PROPORTION test: test  positive (%.3f); test negative (%.3f) class' %(ytest.value_counts()[1]/ytest.shape[0], ytest.value_counts()[0]/ytest.shape[0]))
    
    return Xtrain, Xtest, ytrain, ytest

#
#******************************************************************************
# Run the main script for tuning and training
#******************************************************************************
    
if __name__ == '__main__':
    print("preprocess_traintestsplit.__name__ set to ", __name__ )
else:
    print('preprocess_traintestsplit mod is imported into another module')