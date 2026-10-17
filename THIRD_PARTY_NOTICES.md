# Third-Party Notices

Eye Tracking itself is licensed under the MIT License (`LICENSE`). It uses and, in its release disk images, redistributes the following third-party components.

## MediaPipe Tasks C API (`libmediapipe.dylib`)

- Source: the PyPI wheel `mediapipe==1.1.1` for macOS arm64 (`mediapipe/tasks/c/libmediapipe.dylib`), downloaded and checksum-verified by `scripts/fetch_mediapipe.sh`. The only modification is the install name (`@rpath/libmediapipe.dylib`) and the code signature.
- Copyright: The MediaPipe Authors.
- License: Apache License 2.0.
- The library contains further open source components; their notices ship with the wheel as `NOTICE`. Both files are copied into every app bundle as `Contents/Resources/MediaPipe-LICENSE.txt` and `Contents/Resources/MediaPipe-NOTICE.txt`.

## MediaPipe Face Landmarker model (`face_landmarker.task`)

- Source: `https://storage.googleapis.com/mediapipe-models/face_landmarker/face_landmarker/float16/1/face_landmarker.task`, downloaded and checksum-verified by `scripts/fetch_mediapipe.sh`, unmodified.
- Copyright: Google LLC.
- License: Apache License 2.0.

## MediaPipe C API headers

- Location: `Packages/EyeCore/Sources/CMediaPipe/vendor/mediapipe/`, taken unmodified from the MediaPipe repository at tag `v1.1.1`.
- Copyright: The MediaPipe Authors.
- License: Apache License 2.0, full text in `Packages/EyeCore/Sources/CMediaPipe/vendor/LICENSE`.
