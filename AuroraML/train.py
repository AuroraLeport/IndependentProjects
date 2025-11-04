# this file is the main driver for the machine learning pipeline.

# Import necessary libraries and functions from separate modules
from preprocessing import DataPreprocessing
from model import train_model
from Prod_QA import ouput_qa_artifacts

FILE_PATH = '/Users/auroraleport/Desktop/MyGit/IndependentProjects/Windfall_aleport/data/raw/windfall_ds_challenge/'

def main():
    """
    Main function to run the entire ML pipeline.
    """
    DataPreprocessing = DataPreprocessing(["{FILE_PATH}/label.csv", f"{FILE_PATH}/donation.csv", f"{FILE_PATH}/feature.csv"])
    
    full_df = DataPreprocessing.engineer_features()
    
    X_train, X_test, y_train, y_test = DataPreprocessing.preprocess_data(full_df)
    if X_train is None or y_train is None:
        print("Pipleine is terminated due to data preprocessing error.")
            return
    
    model = train_model(X_train, y_train)
    if model is None:
        print("Pipleine is terminated due to model training error.")
        return
    
    ouput_qa_artifacts(model, X_test, y_test)

if __name__ == "__main__":
    main()