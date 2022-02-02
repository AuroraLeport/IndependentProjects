Introduction
------------
CREATOR: AURORA LEPORT <br />
DATE: 2/1/2022 <br />
PURPOSE: Modeling donors with past 5 years of donor history that will or will not become an ideal donor. <br />
         (ideal = donate >= $20,000 in next 5 years). <br />

/******************

## Installation

The Anaconda distribution of Python is required.  <br />
The code should run with no issues using Python versions 3.8. <br />
Install hyperopt from PyPl (pip install hyperopt). <br />

 ## Project Organization
------------
    ├── README.md          <- The top-level README for developers using this project.
    ├── data
    │   ├── params         <- parameters used to create final model.
    │   │   ├── 1.0-akr-idealdonor-XGB-20220201-colnames.pkl
    │   │   └── 1.0-akr-idealdonor-XGB-20220201-params.npy
    │   │
    │   ├── predictions    <- model predictions (test set). columns: [ID, ytrue, ypred].
    │   │
    │   └── raw            <- raw data
    │       │
    │       ├── donations.csv
    │       ├── major_donor_labels.csv
    │       └── windfall_features.csv
    │
    ├── models             <- Trained and serialized model.
    │
    ├── notebooks          <- Jupyter notebooks and source code.
    │   │   
    │   ├── -exploration.ipynb    <- notebook used to explore raw data and perform feature engineering                              
    │   │
    │   ├── -metricsviz.ipynb     <- notebook used to produce visualizations and metrics.
    │   │
    │   ├── -model.ipynb          <- notebook used to build the model and produce predictions.
    │   │
    │   ├── models            <- Source code to run model.
    │   │   ├── train_predict_model_xgb_tpe.py
    │   │   └── __init__.py           <- Makes models a Python module
    │   │
    │   ├── preprocess            <- Source code to run preprocessing scripts.
    │   │   ├── featureengineering.py
    │   │   └── preprocess_traintestsplit.py
    │   │   └── __init__.py           <- Makes preprocess a Python module
    │   │
    └── └── visualization            <- Source code to run visualization scripts.
            ├── visualize.py
            └── __init__.py           <- Makes visualization a Python module


## Summary of data preprocessing and feature engineering
------------

1.0-akr-idealdonor-exploration.ipynb --> notebook exploring raw data. <br />
    Exploring df_features  <br />
    Creating features to be used for model creation from df_features <br />
    Creating features to be used for model creation from df_donations <br />

date of prediction for model creation (aka PredictedOn) = '2016-08-01'. <br />
any donations after PredictedOn is a future donation any donoation prior to PredictedOn is a historical donation. <br />
this model is limited to donoations in historical 5 years.

Explanation of chosen model parameters -->
Features used for model creation:
       'primaryPropertyValue', 
       'propertyCount', 
       'NetWorth',
       'primaryPropertyLoanToValue_ideal',
       'primaryPropertyValueToNetWorth_ratio', 
       'LoanAmount',
       'amount_prev360d2', 'amount_prev360d3', 
       'amount_prev360d4',
       'amount_prev360d5', 'count_trans_date_prev5y', 
       'random_value',
       'amountscaled_prev360d3', 
       'amountscaled_prev360d5' 
Any features eliminated from df_features was done so because there was minimal correlation with the amount donated between '2016-08-01' and '2021-07-31'. See correlation matrix in 1.0-akr-idealdonor-exploration.ipynb
       
Things to note:
    # there are very few donors of class A and may therefore have very little predictive power. The client should be made aware of this if they are interested in predicting donors of 
Class A. i.e. If we are trying to predict class A donors as ideal or not ideal, this may not be the model to do it! 
    # as we do not have data on period of time a donor is eligibile, I am making a pretty big assumption that the donations dataset holds **all** the historical donation data of a 
candidate.
    # i.e. if a candidate does not have a record of donation, this model assumes they donated amount = 0. It does not assume their donation history is null.
    # date of prediction = '2016-08-01'. Anything donated after is a future donation anything prior is a historical donation.
    

## Explanation of model algorithm choice.
------------
1.0-akr-idealdonor-model.ipynb --> notebook to implement preprocessing, feature engineering, model creation and predictions.

xgb was chosen because
    features are right skewed. Tree based algos can handle this.
    features are more interpretable when they are not transformed. It takes less effort to leave them as is rather than have to scale/transform them and then scale them back for interpretablility. tree based methods do not require transformation/scaling.
    the problem space is non-linear. A tree based approach is therefore appropriate.
    a weight can be added to xgb to balance a highly imballanced dataset.   
    
 Tree-structured Parzen Estimator hyperopt was chosen because
     it optimizes hyperparameter combinations and tries only those values which give the best results ignoring others.
     less time is needed to explore the paramater space vs randomized grid search.

###### [Hyperopt Documentation] (http://hyperopt.github.io/hyperopt/)

1.0-akr-idealdonor-metricsviz.ipynb --> metrics and figures of model performance
    cumulative gains and lift charts
    auc roc and auc precision/recall
    confusion matrix
    distribution of propensity across ideal and non-ideal donors
    distribution of propensity across ideal Classes (checking for bias towards one class or another)
    
## Advice for how to use the model for decision making to achieve the business objective
------------
    This model can be used to predict the likelyhood of a donor to become an "ideal donor" in the next 5 years. 
    
    It is based off of members with a 5 year donor history. 
    
    lift charts: if the client can reach 10 percent of donors they will find x 8.6 as many ideal donors with the model as at random selection.
    
    Precision at ~count ideal candidates:
    model :  if 119 are contacted, 65 are found
    chance:  if 119 are contacted, 0 are found 
    
    there are very few donors of Class A. Class A may have very little predictive power. The client should be made aware of this if they are specifcially interested in
    predicting donors of Class A. i.e. If we are trying to predict Class A donors as ideal or not ideal, this may not be the model to do it! 



