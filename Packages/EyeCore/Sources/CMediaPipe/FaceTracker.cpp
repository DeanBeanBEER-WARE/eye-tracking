#include "CMediaPipe.h"

#include <dlfcn.h>

#include <array>
#include <cstdio>
#include <string>
#include <vector>

#include "mediapipe/tasks/c/core/common.h"
#include "mediapipe/tasks/c/vision/face_landmarker/face_landmarker.h"

namespace {
struct Api {
    decltype(&MpFaceLandmarkerCreate) create = nullptr;
    decltype(&MpFaceLandmarkerDetectForVideo) detectForVideo = nullptr;
    decltype(&MpFaceLandmarkerCloseResult) closeResult = nullptr;
    decltype(&MpFaceLandmarkerClose) close = nullptr;
    decltype(&MpImageCreateFromUint8Data) createImage = nullptr;
    decltype(&MpImageFree) freeImage = nullptr;
    decltype(&MpErrorFree) freeError = nullptr;
};

void copyError(char *destination, int32_t length, const char *message) {
    if (destination != nullptr && length > 0) {
        std::snprintf(destination, static_cast<size_t>(length), "%s", message != nullptr ? message : "unknown error");
    }
}

template <typename Function>
bool resolve(void *library, const char *name, Function &function) {
    function = reinterpret_cast<Function>(dlsym(library, name));
    return function != nullptr;
}
}

struct CMPFaceTracker {
    Api api;
    MpFaceLandmarkerPtr landmarker = nullptr;
    std::array<float, CMP_LANDMARK_COUNT * 3> landmarks{};
    std::vector<float> blendshapes;
    std::vector<std::string> blendshapeNames;
    std::array<float, 16> matrix{};
    bool hasMatrix = false;
};

extern "C" CMPFaceTracker *cmp_face_tracker_create(
    const char *libraryPath, const char *modelPath, const char *caBundlePath, char *error, int32_t errorLength) {
    void *library = dlopen(libraryPath, RTLD_NOW | RTLD_LOCAL);
    if (library == nullptr) {
        copyError(error, errorLength, dlerror());
        return nullptr;
    }
    Api api;
    if (!resolve(library, "MpFaceLandmarkerCreate", api.create)
        || !resolve(library, "MpFaceLandmarkerDetectForVideo", api.detectForVideo)
        || !resolve(library, "MpFaceLandmarkerCloseResult", api.closeResult)
        || !resolve(library, "MpFaceLandmarkerClose", api.close)
        || !resolve(library, "MpImageCreateFromUint8Data", api.createImage)
        || !resolve(library, "MpImageFree", api.freeImage) || !resolve(library, "MpErrorFree", api.freeError)) {
        copyError(error, errorLength, "libmediapipe.dylib lacks a required face landmarker symbol");
        return nullptr;
    }
    MpFaceLandmarkerOptions options{};
    options.base_options.model_asset_path = modelPath;
    options.base_options.file_descriptor = -1;
    options.base_options.delegate = MP_DELEGATE_CPU;
    options.base_options.host_environment = MP_HOST_ENVIRONMENT_UNKNOWN;
    options.base_options.host_system = MP_HOST_SYSTEM_MAC;
    options.base_options.ca_bundle_path = caBundlePath;
    options.running_mode = MP_RUNNING_MODE_VIDEO;
    options.num_faces = 1;
    options.min_face_detection_confidence = 0.5f;
    options.min_face_presence_confidence = 0.5f;
    options.min_tracking_confidence = 0.5f;
    options.output_face_blendshapes = true;
    options.output_facial_transformation_matrixes = true;
    options.result_callback = nullptr;
    MpFaceLandmarkerPtr landmarker = nullptr;
    char *mediapipeError = nullptr;
    if (api.create(&options, &landmarker, &mediapipeError) != kMpOk) {
        copyError(error, errorLength, mediapipeError);
        if (mediapipeError != nullptr) {
            api.freeError(mediapipeError);
        }
        return nullptr;
    }
    auto *tracker = new CMPFaceTracker();
    tracker->api = api;
    tracker->landmarker = landmarker;
    return tracker;
}

extern "C" int32_t cmp_face_tracker_detect(
    CMPFaceTracker *tracker, const uint8_t *rgb, int32_t width, int32_t height, int64_t timestampMs, char *error,
    int32_t errorLength) {
    const Api &api = tracker->api;
    MpImagePtr image = nullptr;
    char *mediapipeError = nullptr;
    if (api.createImage(kMpImageFormatSrgb, width, height, rgb, width * height * 3, &image, &mediapipeError) != kMpOk) {
        copyError(error, errorLength, mediapipeError);
        if (mediapipeError != nullptr) {
            api.freeError(mediapipeError);
        }
        return -1;
    }
    MpFaceLandmarkerResult result{};
    MpStatus status = api.detectForVideo(tracker->landmarker, image, nullptr, timestampMs, &result, &mediapipeError);
    api.freeImage(image);
    if (status != kMpOk) {
        copyError(error, errorLength, mediapipeError);
        if (mediapipeError != nullptr) {
            api.freeError(mediapipeError);
        }
        return -1;
    }
    int32_t found = 0;
    if (result.face_landmarks_count > 0 && result.face_landmarks[0].landmarks_count >= CMP_LANDMARK_COUNT) {
        found = 1;
        const MpNormalizedLandmark *points = result.face_landmarks[0].landmarks;
        for (int index = 0; index < CMP_LANDMARK_COUNT; ++index) {
            tracker->landmarks[index * 3] = points[index].x;
            tracker->landmarks[index * 3 + 1] = points[index].y;
            tracker->landmarks[index * 3 + 2] = points[index].z;
        }
        tracker->blendshapes.clear();
        if (result.face_blendshapes_count > 0) {
            const MpCategories &categories = result.face_blendshapes[0];
            tracker->blendshapes.assign(categories.categories_count, 0.0f);
            if (tracker->blendshapeNames.size() != categories.categories_count) {
                tracker->blendshapeNames.assign(categories.categories_count, std::string());
            }
            for (uint32_t index = 0; index < categories.categories_count; ++index) {
                const MpCategory &category = categories.categories[index];
                if (category.index < 0 || static_cast<uint32_t>(category.index) >= categories.categories_count) {
                    continue;
                }
                tracker->blendshapes[category.index] = category.score;
                if (category.category_name != nullptr) {
                    tracker->blendshapeNames[category.index] = category.category_name;
                }
            }
        }
        tracker->hasMatrix = false;
        if (result.facial_transformation_matrixes_count > 0) {
            const MpMatrix &matrix = result.facial_transformation_matrixes[0];
            if (matrix.rows == 4 && matrix.cols == 4 && matrix.data != nullptr) {
                for (int index = 0; index < 16; ++index) {
                    tracker->matrix[index] = matrix.data[index];
                }
                tracker->hasMatrix = true;
            }
        }
    }
    api.closeResult(&result);
    return found;
}

extern "C" const float *cmp_face_tracker_landmarks(const CMPFaceTracker *tracker) {
    return tracker->landmarks.data();
}

extern "C" int32_t cmp_face_tracker_blendshape_count(const CMPFaceTracker *tracker) {
    return static_cast<int32_t>(tracker->blendshapes.size());
}

extern "C" const float *cmp_face_tracker_blendshape_scores(const CMPFaceTracker *tracker) {
    return tracker->blendshapes.data();
}

extern "C" const char *cmp_face_tracker_blendshape_name(const CMPFaceTracker *tracker, int32_t index) {
    if (index < 0 || static_cast<size_t>(index) >= tracker->blendshapeNames.size()) {
        return "";
    }
    return tracker->blendshapeNames[static_cast<size_t>(index)].c_str();
}

extern "C" int32_t cmp_face_tracker_has_matrix(const CMPFaceTracker *tracker) {
    return tracker->hasMatrix ? 1 : 0;
}

extern "C" const float *cmp_face_tracker_matrix(const CMPFaceTracker *tracker) {
    return tracker->matrix.data();
}

extern "C" void cmp_face_tracker_destroy(CMPFaceTracker *tracker) {
    if (tracker == nullptr) {
        return;
    }
    char *mediapipeError = nullptr;
    if (tracker->landmarker != nullptr && tracker->api.close(tracker->landmarker, &mediapipeError) != kMpOk
        && mediapipeError != nullptr) {
        tracker->api.freeError(mediapipeError);
    }
    delete tracker;
}
