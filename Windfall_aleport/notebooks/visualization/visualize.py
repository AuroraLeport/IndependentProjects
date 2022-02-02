#----------------------------------------------------------------
# import packages
#----------------------------------------------------------------
import pandas as pd
import numpy as np
from numpy import sqrt
from numpy import argmax
from sklearn.metrics import roc_auc_score, roc_curve, auc, precision_recall_curve, average_precision_score, confusion_matrix

import pickle

import matplotlib.pyplot as plt 
import matplotlib
import seaborn as sns
#%matplotlib inline

sns.set(style="whitegrid", color_codes=True)

#******************************************************************************
# Plot gains and lift
#******************************************************************************

def plot_cumgains_lift(file_name, label, random=0.50, color='orange'):
    
    # load data 
    df_plot = pd.read_csv(file_name)
    
    target_mbr = df_plot.loc[df_plot.Ytrue==1, 'ID'] # IDs of true positives
    k_realPOS = target_mbr.shape[0]                  # true positive size
    k_total = df_plot.shape[0]                       # population size

    pct_to_pick = np.arange(.05, 1.05, 0.05)
    tpr_decile = np.zeros(len(pct_to_pick))

    for i in range(len(pct_to_pick)):
        k_pick = int(np.ceil(pct_to_pick[i] * k_total)) # choosing number of predicted positives

        # Identify the top k_pick predicted members (candidate members).
        k_pick_mbrID = df_plot.nlargest(k_pick, 'Ypred').ID

        # Check how many target members are included in our list of candidates (True Positives).
        tp = k_pick_mbrID.isin(target_mbr).sum() # number of true positives when we select by top x% predicted

        # percent true positives at each pct_to_pick. k_realPOS might be lower if chance is lower than random. 
        tpr_decile[i]  = tp / float(k_realPOS) 
    
    plt.figure(figsize=(16,7))
    lw = 2

    # lift chart
    ax1 = plt.subplot(122)
    ax1.plot(pct_to_pick, tpr_decile / pct_to_pick, color=color, marker='o', linestyle='--', markersize=8,
             lw=lw, label=label)
    
    # lift chart random guess
    ax1.plot(pct_to_pick, 
             np.ones(len(pct_to_pick)), 
             color='black', 
             marker='*', 
             markersize=8, 
             lw=lw, 
             linestyle='--', 
             label=f'Random {random}')
    
    #plt.xlim([0.0, 1.0])
    #plt.ylim([0.0, 4])
    ax1.set_xticks(np.arange(.0, 1.10, 0.1))
    ax1.set_xlabel('Total Pop Evaluated (fraction)', fontsize=12, fontweight='bold')
    ax1.set_ylabel('Lift', fontsize=12, fontweight='bold')
    ax1.set_title('Lift Chart', fontsize=12, fontweight='bold')
    ax1.legend(loc='upper right')
    
    
    # Cumulative Gains Chart 
    ax2 = plt.subplot(121)
    ax2.plot(np.append(np.zeros(1), pct_to_pick), 
             np.append(np.zeros(1), tpr_decile), 
             color=color, marker='o', linestyle='--', markersize=8, lw=lw, label=label)
    
    # Cumulative Gains Chart random guess
    ax2.plot(np.append(np.zeros(1), pct_to_pick), 
             np.append(np.zeros(1), pct_to_pick),
             color='black', marker='*', markersize=8, linestyle='--', 
             lw=lw, label=f'Random {random}')
    
    ax2.set_xlim([0, 1.0])
    #ax2.set_ylim([0, 2.0])
    ax2.set_xlabel('Total Pop Evaluated (fraction)', fontsize=12, fontweight='bold')
    ax2.set_ylabel('Diseased Pop Evaluated (fraction)', fontsize=12, fontweight='bold')
    ax2.set_title('Cumulative Gains Chart', fontsize=12, fontweight='bold')
    ax2.legend(loc='lower right')
    
    plt.show();
    
    return pct_to_pick, tpr_decile, k_realPOS, k_total

#******************************************************************************
# Plot area under the curve: roc, pr
#******************************************************************************

def plot_aucroc_aucpr(file_name):
    '''
    Args:
        file_name (str): name of df containing ID (str), Ytrue (int), Ypred (float).
    Returns:
        two plots: auc roc curve, auc pr curve with their respecitive best threholds.
    ''' 
    df = pd.read_csv(file_name)

    # calculate the fpr and tpr at each threshold of the classification
    fpr_model, tpr_model, AUC_thresholds = roc_curve(df['Ytrue'], df['Ypred'])
    # calculate the geometric-mean for each threshold
    gmeans = sqrt(tpr_model * (1-fpr_model))
    # locate the index of the largest g-mean
    AUC_ix = argmax(gmeans)
    
    # calculate the prec and recall at each threshold of the classification
    prec_model,  rec_model, PR_thresholds = precision_recall_curve(df['Ytrue'], df['Ypred'], pos_label=1)
    # cacluate the harmonic mean using f score
    fscore = 2 * (prec_model * rec_model) / (prec_model + rec_model)
    # convert nan to zero
    fscore = np.where(np.isnan(fscore),0,fscore)
    # locate the index of the largest f score
    PR_ix = argmax(fscore)
    
    plt.figure(figsize=(16,7))
    lw = 2
    
    # create subplot: auc roc plot
    ax1 = plt.subplot(121)
    ax1.plot(fpr_model, tpr_model
         #, marker='.'
         , color='red'
         , lw=lw
         , label='Best Model (AUC %.2f)' % auc(fpr_model, tpr_model))
    
    # create marker for threshold with best geometric mean of sensitivity and 1-specificity
    ax1.scatter(fpr_model[AUC_ix], tpr_model[AUC_ix]
                , marker='o'
                , color='red'
                , label='(Thresh=%.4f, Gmean=%.2f)' %(AUC_thresholds[AUC_ix], gmeans[AUC_ix]))
    
    # auc roc no skill line
    ax1.plot([0, 1], [0, 1], 
        color='black', lw=lw, linestyle='--', 
        label='No Skill (AUC 0.50)')
    
    # set graph parameters
    ax1.set_xlabel('1-Specificity (FPR)', fontsize=12, fontweight='bold') # (False Positive Rate)
    ax1.set_ylabel('Sensitivity (TPR)', fontsize=12, fontweight='bold')   # (True Positive Rate)
    ax1.set_title('ROC curve and AUC score', fontsize=12, fontweight='bold')
    ax1.legend(loc='lower right')
    
    # create subplot: auc pr plot
    ax2 = plt.subplot(122)
    # PR curve for ModelX
    ax2.plot(rec_model, prec_model, color='blue', lw=lw, label='Best Model (PR-AUC %.2f)' %auc(rec_model, prec_model)) 
    
    # create marker for threshold with best harmonic mean (f-score) of precision and recall
    ax2.scatter(rec_model[PR_ix], prec_model[PR_ix]
                , marker='o'
                , color='blue'
                , label='(Thresh=%.4f, Fscore=%.2f)' %(PR_thresholds[PR_ix], fscore[PR_ix]))

    # random guess line (chance)
    no_skill = len(df[df['Ytrue']==1]) / len(df['Ytrue'])
    ax2.plot([0, 1], [no_skill, no_skill]
             , color='black'
             , linestyle='--'
             , label='Random %.3f' %no_skill)
    
    # set graph parameters
    ax2.set_xlim([0.0, 1.0])
    ax2.set_ylim([0.0, 1.05])
    ax2.set_xlabel('Recall (Sensitivity)', fontsize=12, fontweight='bold')
    ax2.set_ylabel('Precision (Positive Predictive Value)', fontsize=12, fontweight='bold')
    ax2.set_title('Precision-Recall Curve', fontsize=12, fontweight='bold')
    ax2.legend(loc='upper right')

    plt.show()

#******************************************************************************
# Confusion Matrix
#******************************************************************************

def get_confusion_matrix(file_name, model_name, thresh=0.50):
    '''
    If the argument `thresh` isnt't passed in, the default 0.50 is used.
    
    Args:
        file_name (str):  name of df containing ID (str), Ytrue (int), Ypred (float).
        model_name (str): name of saved model.
        thresh (float): value to classify all Ypred greater than threshold as 1 and lesser than threshold as 0.
    Prints:
        performance metrics of the classification model for which true values are known.
    Returns:
        a dataframe with actual values as rows and predicted values as columns.
    ''' 
    # load data and model
    df = pd.read_csv(file_name)
    fitted_model = pickle.load(open(model_name, "rb"))

    # Get confusion matrix at desired threshold
    target_pct = (df['Ytrue'].value_counts()[1]/df['Ytrue'].shape[0])
    Ypred_thresholded = np.where(np.asarray(df['Ypred'])>thresh,1,0)
    cf_matrix = confusion_matrix(df['Ytrue'], Ypred_thresholded)
    tn, fp, fn, tp = cf_matrix.ravel()
    cf_matrix = pd.DataFrame(cf_matrix
                             , index = ["Actual: Negative", "Actual: Positive"]
                             , columns = ["Predicted: Negative", "Predicted: Positive"])
    
    # metrics to display
    total = tn+fn+tp+fp
    actual_positive = tp+fn
    actual_negative = tn+fp
    predicted_positive = tp+fp
    predicted_negative = tn+fn
    sensitivity = tp/actual_positive
    specificity = tn/actual_negative
    lift = sensitivity/target_pct
    
    print('Threshold      : %.2f' %thresh)
    print('Actual Positives    = %d  Actual Negatives    = %d' % (actual_positive, actual_negative)) # k_POS + k_NEG = k_total
    print('Predicted Positives = %d  Predicted Negatives = %d' % (predicted_positive, predicted_negative)) # k_predPOS + k_predNEG = k_total
    print("precision                      : %.2f" %(tp/predicted_positive)) #ability to designate an individual who has a disease
    print("sensitivity (TPR)              : %.2f" %(sensitivity)) #ability to designate an individual who has a disease
    print("specificity (TNR)              : %.2f" %(specificity)) #ability to designate an individual who does not have a disease
    print("chance                         : %.2f" %(target_pct))
    #print("lift                           : %.2f" %lift)
    print(' ')
    print("model :  if %d are contacted, %d are found" %(predicted_positive, tp))
    print("chance:  if %d are contacted, %d are found \n" %(predicted_positive, predicted_positive*target_pct))

    return cf_matrix

#******************************************************************************
# Run the main script for tuning and training
#******************************************************************************
    
if __name__ == '__main__':
    print("visualize.__name__ set to ", __name__ )
else:
    print('visualize mod is imported into another module')