%% ETRA 解析テンプレート — MATLAB 基本解析
% =============================================
% 使用方法:
%   1. このファイルを personal/<username>/ にコピー
%   2. BUCKET / INPUT_KEY / OUTPUT_PREFIX を変更
%   3. Amazon DCV 経由で EC2 上の MATLAB で実行
%
% 前提: MATLAB R2024b, AWS SDK for MATLAB (matlab-aws-sdk) または AWS CLI 経由

%% 設定
BUCKET        = 'etra-dev-workspace';
INPUT_KEY     = 'personal/<your-user-id>/input/data.csv';
OUTPUT_PREFIX = 'personal/<your-user-id>/results/';

%% S3 からデータ読み込み
% AWS CLI 経由で一時ファイルにダウンロード
tmp_input = tempname;
cmd = sprintf('aws s3 cp s3://%s/%s %s', BUCKET, INPUT_KEY, tmp_input);
status = system(cmd);
if status ~= 0
    error('S3 からのダウンロードに失敗しました: %s', INPUT_KEY);
end

data = readtable(tmp_input);
delete(tmp_input);
fprintf('データ読み込み完了: %d 行 x %d 列\n', height(data), width(data));

%% 基本統計
fprintf('\n=== 基本統計 ===\n');
disp(summary(data));

%% 数値列の解析
num_vars = data.Properties.VariableNames( ...
    varfun(@isnumeric, data, 'OutputFormat', 'uniform'));

if isempty(num_vars)
    warning('数値列が見つかりません');
    return;
end

x = data{:, num_vars{1}};
fprintf('\n対象列: %s\n', num_vars{1});
fprintf('  平均: %.4f\n', mean(x, 'omitnan'));
fprintf('  標準偏差: %.4f\n', std(x, 'omitnan'));
fprintf('  最大: %.4f\n', max(x));
fprintf('  最小: %.4f\n', min(x));

%% フィルタリング（バターワースフィルタ）
fs = 100;                          % サンプリング周波数 [Hz]
fc = 10;                           % カットオフ周波数 [Hz]
[b, a] = butter(4, fc/(fs/2));     % 4次バターワースローパス
x_filtered = filtfilt(b, a, x);

%% プロット
fig = figure('Visible', 'off', 'Position', [0 0 1000 600]);

subplot(2, 1, 1);
t = (0:length(x)-1) / fs;
plot(t, x, 'Color', [0.5 0.5 0.5], 'DisplayName', 'raw'); hold on;
plot(t, x_filtered, 'b', 'DisplayName', 'filtered'); hold off;
legend; xlabel('Time [s]'); ylabel('Amplitude');
title(sprintf('Signal: %s', num_vars{1}));

subplot(2, 1, 2);
[pxx, f] = pwelch(x_filtered, [], [], [], fs);
semilogy(f, pxx);
xlabel('Frequency [Hz]'); ylabel('PSD');
title('Power Spectral Density');

%% 結果を S3 に保存
% 図を PNG として保存
tmp_fig = [tempname '.png'];
exportgraphics(fig, tmp_fig, 'Resolution', 150);
close(fig);

fig_key = [OUTPUT_PREFIX 'signal_plot.png'];
cmd = sprintf('aws s3 cp %s s3://%s/%s --content-type image/png', ...
    tmp_fig, BUCKET, fig_key);
status = system(cmd);
delete(tmp_fig);
if status == 0
    fprintf('図を保存: s3://%s/%s\n', BUCKET, fig_key);
else
    warning('図の保存に失敗しました');
end

% 統計テーブルを CSV として保存
stats_table = table( ...
    {'mean'; 'std'; 'max'; 'min'}, ...
    [mean(x,'omitnan'); std(x,'omitnan'); max(x); min(x)], ...
    [mean(x_filtered,'omitnan'); std(x_filtered,'omitnan'); max(x_filtered); min(x_filtered)], ...
    'VariableNames', {'metric', 'raw', 'filtered'});

tmp_csv = [tempname '.csv'];
writetable(stats_table, tmp_csv);

stats_key = [OUTPUT_PREFIX 'stats.csv'];
cmd = sprintf('aws s3 cp %s s3://%s/%s --content-type text/csv', ...
    tmp_csv, BUCKET, stats_key);
status = system(cmd);
delete(tmp_csv);
if status == 0
    fprintf('統計を保存: s3://%s/%s\n', BUCKET, stats_key);
end

fprintf('\n解析完了\n');
