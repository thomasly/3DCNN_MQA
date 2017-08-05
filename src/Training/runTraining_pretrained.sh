CUDA_VISIBLE_DEVICES=0 th TorchTrainRankingHomogeniousDataset.lua \
-model_name ranking_model_8 \
-dataset_name CASP_SCWRL \
-experiment_name QA_pretraining_clean_e2 \
-datasets_dir /home/lupoglaz/ProteinsDataset/ \
-learning_rate 0.0005 \
-learning_rate_decay 0.1 \
-l2_coef 0.001 \
-tm_score_threshold 0.1 \
-gap_weight 0.1 \
-validation_period 1 \
-model_save_period 10 \
-max_epoch 100 \
-decoys_ranking_mode gdt-ts \
-gpu_num 1 \
-restart \
-restart_epoch 60 \
-restart_dir /home/lupoglaz/Projects/MILA/deep_folder/models/QA_pretraining_clean_ranking_model_8_CASP_SCWRL/models/