# Overlay evals

The [pure model evaluation guide](../../guides/pure_model_evals.md) asks a model
for an EYG program and grades its computed result after checking its type.
Run `gleam test` for offline checks or `gleam run -m overlay/eval/pure -- <model>`
for an actual model request. Failed evaluations exit nonzero.
