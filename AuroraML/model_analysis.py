from typing import List, Any
import pandas as pd
import numpy as np
import pickle
import matplotlib.pyplot as plt
import seaborn as sns
from sklearn.metrics import (
    roc_auc_score,
    precision_score,
    recall_score,
    f1_score,
    confusion_matrix,
    ConfusionMatrixDisplay,
    roc_curve,
    precision_recall_curve,
    auc,
)
from sklearn.inspection import permutation_importance
from numpy import argmax, sqrt
import os

import logging

logging.basicConfig(
    level=logging.INFO, format="%(asctime)s - %(levelname)s - %(message)s"
)


class ModelQA:
    def __init__(
        self,
        artifact_path: str,
        X: pd.DataFrame = None,
        y: np.array = None,
        ID: List[Any] = None,
    ):

        artifact = self._load_artifact(artifact_path)

        # Unpack the contents from the loaded dictionary
        self.model = artifact.get("model")

        self.X_validation = X if X is not None else artifact.get("X_test")
        self.y_validation = y if y is not None else artifact.get("y_test")
        self.ID_validation = ID if ID is not None else artifact.get("ID_test")

        artifact_dir = os.path.dirname(artifact_path)
        self.output_dir = (
            artifact_dir if artifact_dir else "."
        )  # Use current directory if no path is given
        logging.info(f"ModelQA saving plots to: {self.output_dir}")

        if self.model is None or self.X_validation is None:
            logging.error(
                "ModelQA failed to initialize. Check if model and data keys exist in the artifact."
            )

        if (
            self.X_validation is None
            or self.y_validation is None
            or self.ID_validation is None
        ):
            logging.error(
                "Test data is missing. Rerun ModelQA with correct data paths."
            )
            return

        # Check if predict_proba is available (should be for GBC and LR)
        if not hasattr(self.model, "predict_proba"):
            logging.error(
                "Model does not support predict_proba. Cannot calculate lift/gain."
            )
            return

        self.y_proba = self.model.predict_proba(self.X_validation)[:, 1]

        self.df_plot = pd.DataFrame(
            {
                "ID": self.ID_validation.values,
                "y_true": self.y_validation.values,
                "y_pred": self.y_proba,
            }
        )

    def _load_artifact(self, path):
        """Helper to load the single unified artifact file."""
        try:
            with open(path, "rb") as f:
                return pickle.load(f)
        except Exception as e:
            logging.error(f"Failed to load artifact from {path}: {e}")
            return {}

    def evaluate_model_performance(
        self,
        threshold=0.5,
        save_plot: bool = True,
        display_labels: List[str] = ["True Negative", "True Positive"],
    ):
        """
        Calculates and displays core classification metrics (AUROC, Precision, Recall, F1)
        and the Confusion Matrix for a specified classification threshold.
        """

        # Get Hard Predictions (Needed for Precision, Recall, F1)
        y_pred = (self.y_proba >= threshold).astype(int)

        # Calculate Metrics
        try:
            # AUROC (uses probabilities)
            auc = roc_auc_score(self.y_validation, self.y_proba)
            # Classification metrics (uses hard predictions based on threshold)
            precision = precision_score(self.y_validation, y_pred)
            recall = recall_score(self.y_validation, y_pred)
            f1 = f1_score(self.y_validation, y_pred)

            # Display Metrics
            logging.info("-" * 40)
            logging.info(f"Performance Metrics (Threshold: {threshold:.2f})")
            logging.info("-" * 40)
            logging.info(f"AUROC (Area Under ROC Curve): {auc:.4f}")
            logging.info(
                f"Precision (True Positives / Predicted Positives): {precision:.4f}"
            )
            logging.info(f"Recall (True Positives / Actual Positives): {recall:.4f}")
            logging.info(f"F1 Score (Harmonic Mean of Precision and Recall): {f1:.4f}")
            logging.info("-" * 40)

            # Plot Confusion Matrix
            cm = confusion_matrix(self.y_validation, y_pred)
            disp = ConfusionMatrixDisplay(
                confusion_matrix=cm, display_labels=display_labels
            )

            fig, ax = plt.subplots(figsize=(8, 8))
            disp.plot(cmap=plt.cm.Blues, ax=ax)
            ax.set_title(
                f"Confusion Matrix (Threshold: {threshold:.2f})",
                fontsize=14,
                fontweight="bold",
            )

            if save_plot:
                filename = f"confusion_matrix_thresh_{threshold:.2f}.png"
                full_path = os.path.join(self.output_dir, filename)
                fig.savefig(full_path, bbox_inches="tight")  # Save the plot
                logging.info(f"Confusion Matrix saved to {full_path}")
                plt.close(fig)  # Close the figure to free memory
            else:
                plt.show()

            return {
                "AUROC": auc,
                "Precision": precision,
                "Recall": recall,
                "F1_Score": f1,
                "Threshold": threshold,
            }

        except ValueError as e:
            logging.error(
                f"Error calculating metrics. Check if positive class exists and model can predict probabilities. Error: {e}"
            )
            return {}

    def plot_aucroc_aucpr(self, save_plot: bool = True):
        """
        Plots AUROC and Precision-Recall curves, highlighting optimal thresholds.
        """

        # calculate the fpr and tpr at each threshold of the classification
        fpr_model, tpr_model, AUC_thresholds = roc_curve(
            self.df_plot["y_true"], self.df_plot["y_pred"]
        )
        # calculate the geometric-mean for each threshold
        gmeans = sqrt(tpr_model * (1 - fpr_model))
        # locate the index of the largest g-mean
        AUC_ix = argmax(gmeans)

        # calculate the prec and recall at each threshold of the classification
        prec_model, rec_model, PR_thresholds = precision_recall_curve(
            self.df_plot["y_true"], self.df_plot["y_pred"], pos_label=1
        )
        # cacluate the harmonic mean using f score
        fscore = 2 * (prec_model * rec_model) / (prec_model + rec_model)
        # convert nan to zero
        fscore = np.where(np.isnan(fscore), 0, fscore)
        # locate the index of the largest f score
        PR_ix = argmax(fscore)

        plt.figure(figsize=(16, 7))
        lw = 2

        # create subplot: auc roc plot
        ax1 = plt.subplot(121)
        ax1.plot(
            fpr_model,
            tpr_model
            # , marker='.'
            ,
            color="red",
            lw=lw,
            label="Best Model (AUC %.2f)" % auc(fpr_model, tpr_model),
        )

        # create marker for threshold with best geometric mean of sensitivity and 1-specificity
        ax1.scatter(
            fpr_model[AUC_ix],
            tpr_model[AUC_ix],
            marker="o",
            color="red",
            label="(Thresh=%.4f, Gmean=%.2f)"
            % (AUC_thresholds[AUC_ix], gmeans[AUC_ix]),
        )

        # auc roc no skill line
        ax1.plot(
            [0, 1],
            [0, 1],
            color="black",
            lw=lw,
            linestyle="--",
            label="No Skill (AUC 0.50)",
        )

        # set graph parameters
        ax1.set_xlabel(
            "1-Specificity (FPR)", fontsize=12, fontweight="bold"
        )  # (False Positive Rate)
        ax1.set_ylabel(
            "Sensitivity (TPR)", fontsize=12, fontweight="bold"
        )  # (True Positive Rate)
        ax1.set_title("ROC curve and AUC score", fontsize=12, fontweight="bold")
        ax1.legend(loc="lower right")

        # create subplot: auc pr plot
        ax2 = plt.subplot(122)
        # PR curve for ModelX
        ax2.plot(
            rec_model,
            prec_model,
            color="blue",
            lw=lw,
            label="Best Model (PR-AUC %.2f)" % auc(rec_model, prec_model),
        )

        # create marker for threshold with best harmonic mean (f-score) of precision and recall
        ax2.scatter(
            rec_model[PR_ix],
            prec_model[PR_ix],
            marker="o",
            color="blue",
            label="(Thresh=%.4f, Fscore=%.2f)" % (PR_thresholds[PR_ix], fscore[PR_ix]),
        )

        # random guess line (chance)
        no_skill = len(self.df_plot[self.df_plot["y_true"] == 1]) / len(
            self.df_plot["y_true"]
        )
        ax2.plot(
            [0, 1],
            [no_skill, no_skill],
            color="black",
            linestyle="--",
            label="Random %.3f" % no_skill,
        )

        # set graph parameters
        ax2.set_xlim([0.0, 1.0])
        ax2.set_ylim([0.0, 1.05])
        ax2.set_xlabel("Recall (Sensitivity)", fontsize=12, fontweight="bold")
        ax2.set_ylabel(
            "Precision (Positive Predictive Value)", fontsize=12, fontweight="bold"
        )
        ax2.set_title("Precision-Recall Curve", fontsize=12, fontweight="bold")
        ax2.legend(loc="upper right")

        if save_plot:
            filename = "roc_pr_curves.png"
            full_path = os.path.join(self.output_dir, filename)
            plt.savefig(full_path, bbox_inches="tight")
            logging.info(f"ROC/PR Curves saved to {full_path}")
            plt.close()  # plt.close() closes the current figure
        else:
            plt.show()

    def plot_lift_gain(
        self,
        color="blue",
        label="Model",
        random="Guess",
        x_label="Fraction of Pop Evaluated",
        save_plot: bool = True,
    ):

        # Calculate Test Set Constants
        k_total = self.df_plot.shape[0]  # Total population size
        k_realPOS = self.df_plot["y_true"].sum()  # Total True Positives

        if k_realPOS == 0:
            logging.info(
                "Warning: No positive cases in the test set. Cannot plot lift chart."
            )
            return

        # Iteration and Calculation
        pct_to_pick = np.arange(0.05, 1.05, 0.05)
        tpr_decile = np.zeros(len(pct_to_pick))  # True Positive Rate (Gain)

        for i in range(len(pct_to_pick)):
            k_pick = int(np.ceil(pct_to_pick[i] * k_total))

            # Select the top k rows based on prediction score
            top_k_rows = self.df_plot.nlargest(k_pick, "y_pred")

            # Calculate True Positives in the selection
            tp = top_k_rows["y_true"].sum()

            # Calculate True Positive Rate (Gain)
            tpr_decile[i] = tp / float(k_realPOS)

        plt.figure(figsize=(16, 7))
        lw = 2

        # --- Lift Chart ---
        ax1 = plt.subplot(122)
        ax1.plot(
            pct_to_pick,
            tpr_decile / pct_to_pick,
            color=color,
            marker="o",
            linestyle="--",
            markersize=8,
            lw=lw,
            label=label,
        )

        # Lift chart random guess
        ax1.plot(
            pct_to_pick,
            np.ones(len(pct_to_pick)),
            color="black",
            marker="*",
            markersize=8,
            lw=lw,
            linestyle="--",
            label=f"Random {random}",
        )

        ax1.set_xticks(np.arange(0.0, 1.10, 0.1))
        ax1.set_xlabel(x_label, fontsize=12, fontweight="bold")
        ax1.set_ylabel("Lift", fontsize=12, fontweight="bold")
        ax1.set_title("Lift Chart", fontsize=12, fontweight="bold")
        ax1.legend(loc="upper right")

        # --- Cumulative Gains Chart ---
        ax2 = plt.subplot(121)
        ax2.plot(
            np.append(np.zeros(1), pct_to_pick),
            np.append(np.zeros(1), tpr_decile),
            color=color,
            marker="o",
            linestyle="--",
            markersize=8,
            lw=lw,
            label=label,
        )

        # Cumulative Gains Chart random guess
        ax2.plot(
            np.append(np.zeros(1), pct_to_pick),
            np.append(np.zeros(1), pct_to_pick),
            color="black",
            marker="*",
            markersize=8,
            linestyle="--",
            lw=lw,
            label=f"Random {random}",
        )

        ax2.set_xlim([0, 1.0])
        ax2.set_xlabel(x_label, fontsize=12, fontweight="bold")
        ax2.set_ylabel("Gain", fontsize=12, fontweight="bold")
        ax2.set_title("Cumulative Gains Chart", fontsize=12, fontweight="bold")
        ax2.legend(loc="lower right")

        if save_plot:
            filename = "gain_lift_plots.png"
            full_path = os.path.join(self.output_dir, filename)
            plt.savefig(full_path, bbox_inches="tight")
            logging.info(f"Lift/Gain Plots saved to {full_path}")
            plt.close()
        else:
            plt.show()

        # Calculate lift and gain metrics and return a DataFrame
        data = {
            "total_population": pct_to_pick * k_total,
            "target_pop": tpr_decile * k_realPOS,
            "lift": tpr_decile / pct_to_pick,
            "gain": tpr_decile,
        }

        lift_gain_metrics = pd.DataFrame(data, index=pct_to_pick)
        lift_gain_metrics.index.name = "Percent"

        return lift_gain_metrics

    def plot_permutation_importance(
        self, scoring="f1_weighted", n_repeats=10, save_plot: bool = True
    ):
        """
        Calculates and plots the Permutation Importance for the model on the test set.
        This method is agnostic to model type (LR or GBC).
        """
        if self.model is None or self.X_validation is None or self.y_validation is None:
            logging.error(
                "Model or test data is missing. Cannot calculate permutation importance."
            )
            return

        logging.info(f"Calculating Permutation Importance using scoring='{scoring}'...")

        # 1. Calculate Permutation Importance
        # Use the already fitted model (self.model) and the unseen test data.
        # The 'n_jobs=-1' allows for parallel processing to speed up calculation.
        r = permutation_importance(
            self.model,
            self.X_validation,
            self.y_validation,
            scoring=scoring,
            n_repeats=n_repeats,
            random_state=42,
            n_jobs=-1,
        )

        # 2. Organize Results into a DataFrame
        # The importance is the mean decrease in score (r.importances_mean)
        feature_names = self.X_validation.columns

        importance_df = pd.DataFrame(
            {
                "Feature": feature_names,
                "Importance": r.importances_mean,
                "StdDev": r.importances_std,
            }
        )

        # Sort by importance (ascending for barh plot)
        importance_df = importance_df.sort_values(by="Importance", ascending=True)

        # 3. Plotting
        plt.figure(figsize=(10, 8))

        # Plotting the mean importance with error bars for standard deviation
        plt.barh(
            importance_df["Feature"],
            importance_df["Importance"],
            xerr=importance_df["StdDev"],  # Error bars show variability across repeats
            color="skyblue",
        )

        plt.xlabel(f"Decrease in {scoring} Score", fontsize=12, fontweight="bold")
        plt.ylabel("Features", fontsize=12, fontweight="bold")
        plt.title("Permutation Importance (Test Set)", fontsize=14, fontweight="bold")
        plt.tight_layout()

        if save_plot:
            filename = "permutation_importance.png"
            full_path = os.path.join(self.output_dir, filename)
            plt.savefig(full_path, bbox_inches="tight")
            logging.info(f"Permutation Importance saved to {full_path}")
            plt.close()
        else:
            plt.show()

    def plot_model_coefficients(self, top_n=15, save_plot: bool = True):
        """
        Plots the feature coefficients for Logistic Regression models.
        """
        if self.model is None:
            logging.error("Model is missing. Cannot plot coefficients.")
            return

        # 1. Check if the model is Logistic Regression
        if "LR" not in self.model.named_steps:
            logging.error(
                "The pipeline does not contain a Logistic Regression ('LR') step. Cannot plot coefficients."
            )
            # Fallback for GBC
            if "GBC" in self.model.named_steps:
                logging.info(
                    "Model is GBC. Please use plot_permutation_importance instead for feature relevance."
                )
            return

        # Extract feature names and coefficients
        preprocessor = self.model.named_steps["preprocessor"]
        lr_estimator = self.model.named_steps["LR"]

        # Get feature names after OHE and scaling
        feature_names = get_transformed_feature_names(preprocessor)

        # Coefficients from the LR model (handle multi_class='ovr' or single class)
        # Note: coef_ is 2D array (n_classes, n_features) for multi-class, but 1D for binary
        if lr_estimator.coef_.ndim > 1:
            # For binary classification, we care about the coefs for the positive class (index 1)
            coefficients = lr_estimator.coef_[0]
        else:
            coefficients = lr_estimator.coef_

        # Organize and Select Top N (Absolute Value)
        data = (
            pd.DataFrame({"feature": feature_names, "coefficient": coefficients})
            .sort_values(by="coefficient", key=np.abs, ascending=False)
            .head(top_n)
        )

        # Sort again by value for plotting (positive at top, negative at bottom)
        data = data.sort_values(by="coefficient", ascending=True)

        # Plotting

        plt.figure(figsize=(12, max(9, len(data) * 0.4)))

        # Determine colors based on sign (positive/negative impact on log-odds)
        colors = ["red" if c < 0 else "green" for c in data["coefficient"]]

        plt.barh(data["feature"], data["coefficient"], color=colors)

        plt.axvline(x=0, color="gray", linestyle="--")

        plt.xlabel(
            "Coefficient Value (Log-Odds Impact)", fontsize=12, fontweight="bold"
        )
        plt.ylabel("Features", fontsize=12, fontweight="bold")
        plt.title(
            f"Top {top_n} Logistic Regression Feature Coefficients",
            fontsize=14,
            fontweight="bold",
        )
        plt.tight_layout()

        if save_plot:
            filename = "LR_model_coefficients.png"
            full_path = os.path.join(self.output_dir, filename)
            plt.savefig(full_path, bbox_inches="tight")
            logging.info(f"LR Model Coefficients saved to {full_path}")
            plt.close()
            plt.show()

    def plot_kde(
        self,
        hue=None,
        modify_values=None,
        modify_column=None,
        log_scale=True,
        save_plot: bool = True,
    ):
        data = self.X_validation.copy()
        data["y_proba"] = self.y_proba
        data["y_true"] = self.y_validation

        if modify_values:
            data = data[data[modify_column].isin(modify_values)]
        sns.kdeplot(
            data=data,
            x="y_proba",
            hue=hue,
            common_norm=False,
            log_scale=log_scale,
            fill=True,
        )

        if save_plot:
            filename = "kde_plot.png"
            full_path = os.path.join(self.output_dir, filename)
            plt.savefig(full_path, bbox_inches="tight")
            logging.info(f"KDE plot saved to {full_path}")
            plt.close()
        else:
            plt.show()


if __name__ == "__main__":

    artifact_path = (
        "model_runs/Exp001_20251103_101640/Exp001_20251103_101640_artifact.pkl"
    )
    qa_gbc = ModelQA(
        artifact_path=artifact_path,
        # X=X, y=y_true, ID=preprocessed_data['dim_user_id']
    )

    # Run your plots instantly without retraining!
    lift_gain_chart = qa_gbc.plot_lift_gain()
    qa_gbc.plot_permutation_importance()
    # qa_gbc.plot_model_coefficients()  # should convert the log odds impact back to odds ratio scale by exponentiating it (math.exp(x))
    qa_gbc.plot_aucroc_aucpr()

    logging.info("--- Gradient Boosting Classifier Performance ---")
    gbc_metrics = qa_gbc.evaluate_model_performance(threshold=0.5099)
