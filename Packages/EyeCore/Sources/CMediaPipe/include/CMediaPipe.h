#ifndef CMEDIAPIPE_H
#define CMEDIAPIPE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/// The number of face landmarks, including the ten iris landmarks.
#define CMP_LANDMARK_COUNT 478

/// A MediaPipe face landmarker in VIDEO mode, loaded from the MediaPipe Tasks C API at runtime.
///
/// The shim keeps the C++-flavored MediaPipe headers out of Swift and calls the library through `dlopen`, so
/// nothing links against it at build time. Not thread-safe: use one tracker from one serial queue.
typedef struct CMPFaceTracker CMPFaceTracker;

/// Loads the library and creates a landmarker with blendshapes and facial transformation matrices enabled.
///
/// @param libraryPath The path of `libmediapipe.dylib`.
/// @param modelPath The path of `face_landmarker.task`.
/// @param caBundlePath A CA bundle that MediaPipe's usage logging must use; an empty file disables its uploads.
/// @param error Receives a message on failure.
/// @param errorLength The size of `error` in bytes.
/// @return The tracker, or NULL on failure.
CMPFaceTracker *cmp_face_tracker_create(
    const char *libraryPath, const char *modelPath, const char *caBundlePath, char *error, int32_t errorLength);

/// Detects the face in a tightly packed RGB image.
///
/// @param tracker The tracker.
/// @param rgb The pixels, three bytes per pixel, rows without padding.
/// @param width The image width in pixels.
/// @param height The image height in pixels.
/// @param timestampMs A timestamp that increases with every call.
/// @param error Receives a message on failure.
/// @param errorLength The size of `error` in bytes.
/// @return 1 if a face was found, 0 if not, -1 on failure.
int32_t cmp_face_tracker_detect(
    CMPFaceTracker *tracker, const uint8_t *rgb, int32_t width, int32_t height, int64_t timestampMs, char *error,
    int32_t errorLength);

/// The landmarks of the last detected face as x, y, z triples (`CMP_LANDMARK_COUNT` of them); x and y are
/// normalized to the image, z is the relative depth.
const float *cmp_face_tracker_landmarks(const CMPFaceTracker *tracker);

/// The number of blendshape scores of the last detected face.
int32_t cmp_face_tracker_blendshape_count(const CMPFaceTracker *tracker);

/// The blendshape scores of the last detected face, ordered by category index.
const float *cmp_face_tracker_blendshape_scores(const CMPFaceTracker *tracker);

/// The name of a blendshape category, or an empty string for an unknown index.
const char *cmp_face_tracker_blendshape_name(const CMPFaceTracker *tracker, int32_t index);

/// Whether the last detected face has a facial transformation matrix.
int32_t cmp_face_tracker_has_matrix(const CMPFaceTracker *tracker);

/// The facial transformation matrix of the last detected face: 16 floats in column-major order.
const float *cmp_face_tracker_matrix(const CMPFaceTracker *tracker);

/// Closes the landmarker. The library stays loaded for the lifetime of the process.
void cmp_face_tracker_destroy(CMPFaceTracker *tracker);

#ifdef __cplusplus
}
#endif

#endif
