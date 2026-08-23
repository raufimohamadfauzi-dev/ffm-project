package com.ffm_manager

class FfmLocalModelBridge {
    init {
        System.loadLibrary("ffm_local_model_bridge")
    }

    external fun initNative(modelPath: String, mmprojPath: String): Int
    external fun destroyNative()
    external fun generateSingleShotNative(systemPrompt: String, userPrompt: String, imagePath: String?): String
}
