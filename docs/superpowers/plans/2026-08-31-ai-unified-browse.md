# AI Unified Browse Implementation Plan

> Executed inline by the author immediately (user waived gates). Tasks:
1. `model_curation.js` + `tst_model_curation.qml` (TDD): isSurfaced/withToggled/providerIndexOf.
2. Parser name prefix + providerName field; adapt the catalog contract's parser fixture pin if it spells the old name; Config schema `selectedModels: []` on the customProviders example-free default (documented key, no default entries to change); `Ai.pickerModelList` filter through the fold.
3. Browse view merged rows (provider rows from Ai.models via providerIndexOf + selection toggle; OpenRouter rows as today), pins, receipts, deploy, restart.
Conventions as every prior plan; commits gated on green.
