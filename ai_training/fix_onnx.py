import onnx


model = onnx.load(
    "privacy_guardian.onnx"
)


model.ir_version = 9


onnx.save(
    model,
    "privacy_guardian_v9.onnx"
)


print(
    "Converted ONNX IR version:",
    model.ir_version
)