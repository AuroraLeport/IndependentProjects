import pandas as pd
import numpy as np

from sklearn.impute import SimpleImputer
from sklearn.model_selection import train_test_split
from sklearn.preprocessing import StandardScaler, OneHotEncoder, FunctionTransformer
from sklearn.pipeline import Pipeline
from sklearn.compose import ColumnTransformer
from sklearn.ensemble import GradientBoostingClassifier

class Model:
    """
    Initializes the Model class.
    """
    def __init__(self, 
                 df: pd.DataFrame, 
                 label_column: str = "target",
                 id_column: str = 'candidate_id',
                 log_transform_features: list = ['NetWorth', 'primaryPropertyValue']
                 ):

        self.df = df
        self.label_column = label_column
        self.id_column = id_column
        self.log_transform_features = log_transform_features
        
    def preprocess_data(self):
        """
        Performs data preprocessing steps, including splitting and scaling.

        Args:
            df (pd.DataFrame): The feature and target matrix
        """
        
        if self.df is None or self.df.empty:
            print("Preprocessing aborted: Input DataFrame is None or empty.")
            return None, None, None, None
        
        print("Preprocessing data...")
        
        #fset = [x for x in df.columns if x not in self.label_column]
        features_to_drop = [self.label_column] + [self.id_column]
        
        X = self.df.drop(columns=features_to_drop, errors='ignore')
        y = self.df[self.label_column]
        
        # if self.id_column in self.label_column:
        #     y = self.df[self.label_column].drop(columns=[self.id_column])
        
        all_numerical = X.select_dtypes(include=[np.number]).columns.tolist()
        categorical_features = X.select_dtypes(include=['object', 'category']).columns.tolist()
        binary_features = []
        
        # Automatically detect binary features (0, 1, NaN)
        for col in all_numerical:
            unique_values = X[col].dropna().unique()
            if set(unique_values).issubset({0,1}):
                binary_features.append(col)
        
        # Identify log-transformed features
        numerical_features = [col for col in all_numerical if col not in binary_features + self.log_transform_features]
        
                    
        # Create seperate transformers for each data type
        numerical_transformer = Pipeline(steps=[
            ('imputer', SimpleImputer(strategy='constant', fill_value=0)),
            ('scaler', StandardScaler()),
        ])
        
        categorical_transformer = Pipeline(steps=[
            ('imputer', SimpleImputer(strategy='constant', fill_value='-9999')),
            ('onehot', OneHotEncoder(handle_unknown='ignore'))
        ])
        
        binary_transformer = Pipeline(steps=[
            ('imputer', SimpleImputer(strategy='constant', fill_value=0)), 
        ])
        
        log_transformer = Pipeline(steps=[
            ('imputer', SimpleImputer(strategy='constant', fill_value=0)),
            ('log', FunctionTransformer(lambda x: np.log10(x+1))),
            ('scaler', StandardScaler())
        ])
        
        # Use ColumnTransformer to apply the transformations to the correct columns
        preprocessor_transformers = [
            ('num', numerical_transformer, numerical_features),
            ('cat', categorical_transformer, categorical_features),
        ]
        
        if self.log_transform_features:
            preprocessor_transformers.append(('log', log_transformer, self.log_transform_features))
        
        if binary_features:
            preprocessor_transformers.append(('binary', binary_transformer, binary_features))
            
        preprocessor = ColumnTransformer(
            transformers=preprocessor_transformers,
            remainder='passthrough'
        )
        
        # Create the final pipeline
        pipeline = Pipeline(steps=[
            ('preprocessor', preprocessor),
            ('GBC', GradientBoostingClassifier(random_state=42))
        ])
        
        # Fit the pipeline on the training data only and then transform both sets
        X_train, X_test, y_train, y_test = train_test_split(X, y, test_size=0.2, shuffle=True, random_state=42, stratify=y)
        print(f"Data split into training ({X_train.shape}) and testing ({X_test.shape}) sets.")
        
        pipeline.fit(X_train, y_train)
        
        
        #joblib.dump(scaler, f'scaler_{self.project_name}_{self.current_date}.joblib')
            
        return pipeline, X_test, y_test
    
if __name__ == '__main__':
    # Create a dummy DataFrame with an ID column and all feature types
    data = {'id': [101, 102, 103, 104, 105, 106, 107, 108, 109, 110],
            'numerical_1': [1, 2, np.nan, 4, 5, 6, 7, 8, 9, 10],
            'numerical_2': [10, np.nan, 30, 40, 50, 60, 70, 80, 90, 100],
            'highly_skewed_feature': [1, 10, 100, 1000, 10000, 100, 10, 1, 1, 10],
            'categorical_1': ['A', 'B', 'A', 'C', np.nan, 'A', 'B', 'A', 'C', 'C'],
            'categorical_2': [np.nan, 'X', 'Y', 'Z', 'Y', 'X', 'Y', 'Z', 'Y', 'X'],
            'binary_feature': [0, 1, np.nan, 0, 1, 0, 1, 0, 1, np.nan],
            'y_value': [0, 1, 0, 1, 0, 1, 0, 1, 0, 1]}
    
    df = pd.DataFrame(data)
    
    print("Original DataFrame:")
    print(df)
    
    # Create the transformation pipeline by explicitly passing the feature names
    model = Model(df=df, 
                  id_column='id',
                  label_column='y_value',
                  log_transform_features=['highly_skewed_feature'])
    
    transform_pipeline, X_test, y_test, = model.preprocess_data()
    
    print("\nTransformed Training data:")
    print(X_train)
    
    print("\nTransformed Test data:")
    print(X_test)

    
            
    
    