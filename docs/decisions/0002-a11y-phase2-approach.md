# 0002 — a11y フェーズ2 の実装アプローチ

## Context
WCAG 2.1 AA 監査のフェーズ1（Dialog/Confirm/Message の対話系プリミティブ）は実装済み。
フェーズ2の残項目: document.title のビュー連動、フォームラベル、色コントラスト是正、table scope/caption、nav aria-current/aria-label、loading 中の操作無効化、focus 可視化。
対象は frontend/portal の 6 ページ規模。
基準: カバレッジ / 一貫性 / 低リグレッション / 規模に見合う労力。

## Options considered
- **B-inc. 個別属性修正の積み上げ**（その場でラベル/scope/title/コントラスト class を付与）。
- **B-ds. a11y デザインシステム層**（Field/TextInput/DataTable/NavLink を既定化、トークン集中）。

## Decision
**B-inc + 横断2点の共通化（ハイブリッド）を採用**。
大半は属性レベルの個別修正とし、真に横断的な2点だけ集中させる:
(1) `index.css` にグローバル `:focus-visible` スタイル、(2) 小さな `<Field>`（label + input id + error 関連付け）を少数の入力に適用。
table は scope/caption をインライン付与。汎用 DataTable やフルデザインシステムは作らない。
決め手: 6 ページ規模に見合う最小リグレッションで AA をカバーしつつ、横断的な focus 可視化とフォームラベリングのみ集中させ退行を防ぐ。

## Consequences
- 容易になる: 低リスクで段階適用、focus とラベルの既定が1か所に集約。
- 難しくなる/要監視: コントラスト一貫性はレビュー規律に依存（規模的に許容）。Admin/DICOM の表は差異が大きいため generic 化しない判断。
- 次段: フェーズ3（Medium）以降は別途。
