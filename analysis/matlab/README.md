# analysis/matlab

MATLAB 解析スクリプト・テンプレート。

## ディレクトリ構成

```
matlab/
├── templates/
│   └── example_analysis.m   # 基本解析テンプレート
└── README.md
```

## 前提

- Amazon DCV 経由で EC2 に接続し、GUI 付き MATLAB を使用する。
- MATLAB R2024b（Campus-Wide Individual ライセンス）。
- AWS CLI が EC2 インスタンスで使用可能であること（IAM ロール経由）。

## S3 連携

テンプレートは AWS CLI 経由で S3 にアクセスする。

```matlab
% データ読み込み
system('aws s3 cp s3://etra-dev-workspace/personal/<id>/input/data.csv /tmp/data.csv');
data = readtable('/tmp/data.csv');

% 結果保存
system('aws s3 cp /tmp/result.png s3://etra-dev-workspace/personal/<id>/results/result.png');
```

## 注意

- 解析結果は `results/<user-id>/` に保存すること。
- GUI が不要な処理は Python テンプレートも参照すること。
