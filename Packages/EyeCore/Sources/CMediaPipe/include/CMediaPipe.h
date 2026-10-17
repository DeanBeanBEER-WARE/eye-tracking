#ifndef CMEDIAPIPE_H
#define CMEDIAPIPE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define CMP_LANDMARK_COUNT 478

typedef struct CMPFaceTracker CMPFaceTracker;

CMPFaceTracker *cmp_face_tracker_create(
    const char *libraryPath, const char *modelPath, const char *caBundlePath, char *error, int32_t errorLength);

int32_t cmp_face_tracker_detect(
    CMPFaceTracker *tracker, const uint8_t *rgb, int32_t width, int32_t height, int64_t timestampMs, char *error,
    int32_t errorLength);

const float *cmp_face_tracker_landmarks(const CMPFaceTracker *tracker);

int32_t cmp_face_tracker_blendshape_count(const CMPFaceTracker *tracker);

const float *cmp_face_tracker_blendshape_scores(const CMPFaceTracker *tracker);

const char *cmp_face_tracker_blendshape_name(const CMPFaceTracker *tracker, int32_t index);

int32_t cmp_face_tracker_has_matrix(const CMPFaceTracker *tracker);

const float *cmp_face_tracker_matrix(const CMPFaceTracker *tracker);

void cmp_face_tracker_destroy(CMPFaceTracker *tracker);

#ifdef __cplusplus
}
#endif

#endif
