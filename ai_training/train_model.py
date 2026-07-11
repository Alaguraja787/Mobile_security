import pandas as pd
import numpy as np

from sklearn.model_selection import train_test_split
from sklearn.ensemble import RandomForestClassifier

from sklearn.metrics import (
    accuracy_score,
    classification_report,
    confusion_matrix
)

from skl2onnx import convert_sklearn
from skl2onnx.common.data_types import FloatTensorType


# =================================================
# Load Privacy Sentinel Dataset
# =================================================

DATASET_PATH = "privacy_dataset.csv"

df = pd.read_csv(DATASET_PATH)

print("\nDataset Loaded")
print("Shape:", df.shape)


# =================================================
# Data Cleaning
# =================================================

# remove duplicate rows

df = df.drop_duplicates()


# fill missing values

df = df.fillna(0)



# =================================================
# Find Target Column
# =================================================

print("\nColumns:")
print(df.columns)


TARGET = "Class"


if TARGET not in df.columns:
    raise Exception(
        "Target column 'Class' not found. Check dataset column name"
    )


# =================================================
# Split X and y
# =================================================


X = df.drop(
    TARGET,
    axis=1
)


y = df[TARGET]


# Convert all features numeric

X = X.apply(
    pd.to_numeric,
    errors="coerce"
)


X = X.fillna(0)



print(
    "\nTraining Features:",
    X.shape[1]
)


# =================================================
# Train Test Split
# =================================================


X_train, X_test, y_train, y_test = train_test_split(

    X,

    y,

    test_size=0.2,

    random_state=42,

    stratify=y

)



# =================================================
# Model Training
# =================================================


model = RandomForestClassifier(

    n_estimators=200,

    max_depth=25,

    random_state=42,

    n_jobs=-1

)



print("\nTraining started...")


model.fit(

    X_train,

    y_train

)



print("Training completed")



# =================================================
# Model Testing
# =================================================


prediction = model.predict(
    X_test
)


accuracy = accuracy_score(
    y_test,
    prediction
)



print(
    "\nAccuracy:",
    accuracy
)



print(
    "\nClassification Report\n"
)


print(
    classification_report(
        y_test,
        prediction
    )
)



print(
    "\nConfusion Matrix\n"
)


print(
    confusion_matrix(
        y_test,
        prediction
    )
)



# =================================================
# Convert Model to ONNX
# =================================================


feature_count = X.shape[1]


initial_type = [

    (

        "float_input",

        FloatTensorType(

            [None, feature_count]

        )

    )

]



print(
    "\nConverting to ONNX..."
)



onnx_model = convert_sklearn(

    model,

    initial_types=initial_type

)



with open(

    "privacy_guardian.onnx",

    "wb"

) as file:


    file.write(

        onnx_model.SerializeToString()

    )



print(
    "\nprivacy_guardian.onnx created successfully"
)


print(
    "Total Features:",
    feature_count
)