#------------------------------------------------------------------------------ 
# import packages
#------------------------------------------------------------------------------
import numpy as np
import pandas as pd
import xgboost as xgb
from sklearn.model_selection import train_test_split
from sklearn.model_selection import StratifiedKFold
from sklearn.metrics import roc_auc_score, average_precision_score
from hyperopt import fmin, hp, tpe, rand, Trials, STATUS_OK
import pickle

# nested functions
# https://www.analyticsvidhya.com/blog/2021/08/how-nested-functions-are-used-in-python/

# hyperopt documentation
#http://hyperopt.github.io/hyperopt/
#******************************************************************************
# Define functions and module-level variables
#******************************************************************************

# configure parameters
XGB_eta = 0.001 #0.05 #0.2 # 0.01 ~ 0.1
XGB_seed_bst = 0
XGB_bst_rounds = 500 #1000 #500 #3000
XGB_early_stop_rounds = 30 #50

evaluation_metrics = ['aucpr'] #auc #error
verbose = 1
OPT_niter = 10

def get_fixed_params():
    '''
    Module level variables.
    Define the fixed hyper-parameter space.
    '''
    params_fixed = {'booster'         :'gbtree', #dart
                    'objective'       :'binary:logistic',
                    'eta'             :XGB_eta,                                       
                    'seed'            :XGB_seed_bst,
                    'verbosity'       :1,
                    'alpha'           :0, # L1 reg
                    'eval_metric'     : ['aucpr']
                   } 
    
    return params_fixed


def get_param_space():
    '''
    Define the hyper-parameter space to search for the optimal set of values.
    '''
    param_space = {'max_depth'       : hp.quniform('max_depth', 2, 3, 1), # convert to int #3
                   'min_child_weight': hp.uniform('min_child_weight', 1, 30),
                   'scale_pos_weight': hp.uniform('scale_pos_weight', 50, 200),
                   'subsample'       : hp.uniform('subsample', 0.4, 1),
                   'colsample_bytree': hp.uniform('colsample_bytree', 0.2, 1),                  
                   'gamma'           : hp.loguniform('gamma', np.log(1e-4), np.log(1)),
                   'lambda'          : hp.loguniform('lambda', np.log(1e-4), np.log(1))}
    
    return param_space
    
# create nested function closure        
def generate_obj_func(X, y, cv,):
    '''
    Returns a closure obj_xgb.
    Args:
        X, y (numpy array): training data
        cv (object): an sklearn cv fold generator
    '''
    def obj_xgb(params):
        '''
        Objective function to be minimized by hyperopt.fmin.
        Args:
            params (dict): a set of hyper-parameter values sampled from param_space
        Returns:
            a dictionary with keys 'loss', 'num_bst_round' and 'status'
        '''
        # set up booster parameters
        params_bst = get_fixed_params()
        params_bst.update(params)
        params_bst['max_depth'] = int(params_bst['max_depth'])
        
        # split cv folds
        fold_idx = list(cv.split(X=X, y=y))
        
        # format training data
        Xy = xgb.DMatrix(data=X, label=y)
        
        # cross validation
        cv_result = xgb.cv(params = params_bst,
                           dtrain = Xy,
                           num_boost_round = XGB_bst_rounds,
                           early_stopping_rounds = XGB_early_stop_rounds,
                           folds = fold_idx, # nfold, stratified, seed, shuffle                               
                           metrics = evaluation_metrics,
                           fpreproc = None,
                           verbose_eval = True)
        avg_cv_score = cv_result.iloc[-1, 0]
        num_bst_round = cv_result.shape[0]
        
        if verbose == 1:
            print('hyper-parameter values in this trial:')
            print('max_depth        = %d' % params_bst['max_depth'])
            print('min_child_weight = %.4f' % params_bst['min_child_weight'])
            print('scale_pos_weight = %.4f' % params_bst['scale_pos_weight'])
            print('subsample        = %.4f' % params_bst['subsample'])
            print('colsample_bytree = %.4f' % params_bst['colsample_bytree'])
            print('lambda           = %.6f' % params_bst['lambda'])
            print('gamma            = %.6f' % params_bst['gamma'])
            print('cv tuning score = %.8f, n_round = %d' % (avg_cv_score, num_bst_round))
            print('')
            
        return {'loss'         : -avg_cv_score, 
                'num_bst_round': num_bst_round,
                'status'       : STATUS_OK}
    
    return obj_xgb
    

def xgb_param_opt(X, y, cv, method):
    
    obj_func = generate_obj_func(X=X, y=y, cv=cv)
    par_space = get_param_space()
    
    # minimize obj_func in par_space
    # best_pars contains best parameters selected from par_space
    # trls contains info from each trial of parameter search        
    trls = Trials()
    best_pars = fmin(obj_func, 
                     par_space, 
                     algo = method, #tpe.suggest, rand.suggest
                     max_evals = OPT_niter,
                     trials = trls)   
    res = pd.DataFrame([trial['result'] for trial in trls.trials]) # res = pd.DataFrame(trls.results)
    best_score = -(res['loss'].min())
    best_idx = res['loss'].idxmin()
    best_pars['num_boost_round'] = res.loc[best_idx, 'num_bst_round']
    best_pars['max_depth'] = int(best_pars['max_depth'])
    best_pars.update(get_fixed_params())
    
    if verbose == 1:
        print('best hyper-parameters:')
        for pname, pvalue in best_pars.items():
            print('    %s = %r' % (pname, pvalue))
        print('best cv tuning score = %.6f' % best_score)
    
    return best_pars, best_score


def xgb_fit_predict(pars, Xtrain, ytrain, Xtest):

    # convert data format for xgb
    dtrain = xgb.DMatrix(data=Xtrain, label=ytrain)
    dtest = xgb.DMatrix(data=Xtest)
    
    # set up hyper-parameters in the format required by xgb.train
    n_round_bst = pars['num_boost_round']
    params_bst = {key:val for (key,val) in pars.items() if key!='num_boost_round'}
    
    # fit an xgb model on Xtrain, ytrain
    bst = xgb.train(params = params_bst, 
                    dtrain = dtrain, 
                    num_boost_round = n_round_bst, 
                    early_stopping_rounds = None)
    
    # Make predictions on Xtest
    y_pred = bst.predict(data=dtest)

    return y_pred, bst


def xgb_pipeline(Xtrain, ytrain, Xtest, cv, opt_method=tpe.suggest):#=rand.suggest
    
    # tune
    best_params, best_score = xgb_param_opt(X = Xtrain, 
                                            y = ytrain, 
                                            cv = cv, 
                                            method = opt_method
                                            )
    # fit and predict
    y_pred, bst = xgb_fit_predict(pars = best_params,
                                  Xtrain = Xtrain,
                                  ytrain = ytrain,
                                  Xtest = Xtest) 
    
    return y_pred, best_score, best_params, bst

#
#******************************************************************************
# Run the main script for tuning and training
#******************************************************************************
    
if __name__ == '__main__':
    print("train_predict_model_xgb_tpe.__name__ set to ", __name__ )
else:
    print('train_predict_model_xgb_tpe mod is imported into another module')