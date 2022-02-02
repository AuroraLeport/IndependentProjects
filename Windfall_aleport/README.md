### Table of Contents

1. [Installation](#installation)
2. [Project Organization](#ProjectOrganization)
3. [Summary: data exploration](#summary)
4. [Summary: model creation](#modelchoice)
5. [Advice for model usage](#advice)

Introduction
------------
CREATOR: Aurora Leport <br />
DATE: 2/1/2022 <br />
PURPOSE: Modeling donors with past 5 years of donor history that will or will not become an ideal donor. <br />
         (ideal = donate >= $20,000 in next 5 years). <br />

## Installation <a name="installation"></a>

The Anaconda distribution of Python is required.  <br />
The code should run with no issues using Python versions 3.8. <br />
Install hyperopt from PyPl (pip install hyperopt). <br />

 ## Project Organization<a name="ProjectOrganization"></a>
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


## Summary: data exploration  <a name="summary"></a>
------------

1.0-akr-idealdonor-exploration.ipynb --> notebook used for exploration of raw data and feature creation/inclusion. <br />
    * Exploring df_features  <br />
    * Creating features to be used for model creation from df_features <br />
    * Creating features to be used for model creation from df_donations <br />

Explanation of chosen model parameters --> <br />
* Features used for model creation: <br />
       'primaryPropertyValue', <br />
       'propertyCount', <br />
       'NetWorth', <br />
       'primaryPropertyLoanToValue_ideal' : LTV ratio of 80% or less is ideal, <br />
       'primaryPropertyValueToNetWorth_ratio',  <br />
       'LoanAmount', <br />
       'amount_prev360d2': amount donated in 2014-2015, <br />
       'amount_prev360d3': amount donated in 2013-2014,  <br />
       'amount_prev360d4': amount donated in 2012-2013, <br />
       'amount_prev360d5': amount donated in 2011-2012, <br />
       'count_trans_date_prev5y': count donations 2011-Predicted on date, <br />
       'random_value': baseline for feature importance, <br />
       'amountscaled_prev360d3',  <br />
       'amountscaled_prev360d5' <br />
Any features eliminated from df_features was done so because there was minimal correlation with the amount donated between '2016-08-01' and '2021-07-31'. <br />
See correlation matrix in 1.0-akr-idealdonor-exploration.ipynb <br />
As the dataset was pretty small it may have been more beneficial to keep all columns in the dataset. <br />
       
Things to note: <br />
    --> there are very few donors of class A and may therefore have very little predictive power. <br />
         The client should be made aware of this if their main interest is to predict ideal donors from donors of Class A. <br />
         i.e. If we are trying to predict class A donors as ideal or not ideal, this may not be the model to do it! <br />
    --> as we do not have data on period of time a donor is eligibile, I am making a big assumption that the donations dataset holds **all** the historical donation data of a 
         candidate. <br />
         i.e. if a candidate does not have a record of donation, this model assumes they donated amount = 0. It **does not** assume their donation history is null. <br />
    --> date of prediction for model creation (aka PredictedOn) = '2016-08-01'. <br />
         any donations after PredictedOn is a future donation any donoation prior to PredictedOn is a historical donation. <br />
         this model is limited to donoations in historical 5 years.

## Summary: preprocessing, feature engineering, model creation (and explanation of algorithm choice). <a name="modelchoice"></a>
------------
1.0-akr-idealdonor-model.ipynb --> notebook to implement preprocessing, feature engineering, model creation and predictions.

* xgb was chosen because <br />
    tree based methods do not require transformation/scaling and can handel non-linear problem spaces. <br />
    features are right skewed. <br />
    features are more interpretable when they are not transformed. <br />
    It takes less effort to leave them as is rather than have to scale/transform them and then scale them back for interpretablility. <br />
    the problem space is non-linear. <br />
    a weight can be added to xgb to balance a highly imballanced dataset. <br /> 
    
 * Tree-structured Parzen Estimator hyperopt was chosen because <br /> 
     it optimizes hyperparameter combinations and tries only those values which give the best results ignoring others. <br />
     less time is needed to explore the paramater space vs randomized grid search. <br />
     ###### [Hyperopt Documentation] (http://hyperopt.github.io/hyperopt/) <br />
    
## Advice for how to use the model for decision making to achieve the business objective <a name="advice"></a>
------------
1.0-akr-idealdonor-metricsviz.ipynb --> metrics and figures of model performance <br />
    cumulative gains and lift charts <br />
    auc roc and auc precision/recall <br />
    confusion matrix <br />
    distribution of propensity across ideal and non-ideal donors <br />
    distribution of propensity across ideal Classes (checking for bias towards one class or another) <br />
    
    * This model can be used to predict the likelyhood of a donor to become an "ideal donor" in the next 5 years. 
    It is based off of members with a 5 year donor history. 
    
    * lift charts: if the client can reach 10 percent of donors they will find x 8.6 as many ideal donors with the model as at random selection. 

    * Precision using model at the number of ideal candidates typically found in 5 year period:
    model :  if 119 are contacted, 65 are found
    chance:  if 119 are contacted, 0 are found
    
    * There are very few donors of Class A. If we are trying to predict Class A donors as ideal or not ideal, this may not be the model to do it! 



