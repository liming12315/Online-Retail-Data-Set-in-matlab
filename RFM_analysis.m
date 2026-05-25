clear; clc; close all;

%% 1. 读取清洗后的数据

load('cleaned_online_retail.mat');
% 需要包含 T_sales
% T_sales 应该是正常销售数据，不包含取消订单

%% 2. 准备 RFM 数据

RFMData = T_sales;

% 确保关键字段类型
RFMData.CustomerID = string(RFMData.CustomerID);
RFMData.InvoiceNo = string(RFMData.InvoiceNo);

% 去掉缺失 CustomerID 的记录
RFMData = RFMData(~ismissing(RFMData.CustomerID) & RFMData.CustomerID ~= "", :);

% 如果 SalesAmount 不存在，则重新构造
if ~ismember('SalesAmount', RFMData.Properties.VariableNames)
    RFMData.SalesAmount = RFMData.Quantity .* RFMData.UnitPrice;
end

% 观察日：数据截止 2011-12-09，取下一天
analysisDate = datetime(2011,12,10);

fprintf('用于RFM分析的交易明细数：%d\n', height(RFMData));
fprintf('客户数：%d\n', numel(unique(RFMData.CustomerID)));

%% 3. 按 CustomerID 聚合计算 RFM

[G_customer, customerList] = findgroups(RFMData.CustomerID);

% 最近一次购买日期
LastPurchaseDate = splitapply(@max, RFMData.InvoiceDate, G_customer);

% Recency：距观察日天数
Recency = days(analysisDate - LastPurchaseDate);

% Frequency：购买次数，按 InvoiceNo 去重
Frequency = splitapply(@(x) numel(unique(x)), RFMData.InvoiceNo, G_customer);

% Monetary：总消费金额
Monetary = splitapply(@sum, RFMData.SalesAmount, G_customer);

% 平均订单金额
AvgOrderValue = Monetary ./ Frequency;

% 活跃天数
ActiveDays = splitapply(@(x) numel(unique(dateshift(x, 'start', 'day'))), ...
    RFMData.InvoiceDate, G_customer);

RFM = table(customerList(:), LastPurchaseDate(:), Recency(:), ...
    Frequency(:), Monetary(:), AvgOrderValue(:), ActiveDays(:), ...
    'VariableNames', {'CustomerID', 'LastPurchaseDate', 'Recency', ...
    'Frequency', 'Monetary', 'AvgOrderValue', 'ActiveDays'});

% 去除金额异常客户
RFM = RFM(RFM.Monetary > 0, :);

disp('RFM样例：');
disp(RFM(1:min(10,height(RFM)), :));

%% 4. 一次性购买客户比例

oneTimeBuyerCount = sum(RFM.Frequency == 1);
oneTimeBuyerRatio = oneTimeBuyerCount / height(RFM);

fprintf('\n====== 一次性购买客户 ======\n');
fprintf('一次性购买客户数：%d\n', oneTimeBuyerCount);
fprintf('一次性购买客户比例：%.2f%%\n', oneTimeBuyerRatio * 100);
fprintf('==========================\n');

%% 5. RFM 描述性统计

fprintf('\n====== RFM描述性统计 ======\n');
fprintf('客户总数：%d\n', height(RFM));
fprintf('平均Recency：%.2f天\n', mean(RFM.Recency));
fprintf('Recency中位数：%.2f天\n', median(RFM.Recency));
fprintf('平均Frequency：%.2f次\n', mean(RFM.Frequency));
fprintf('Frequency中位数：%.2f次\n', median(RFM.Frequency));
fprintf('平均Monetary：%.2f\n', mean(RFM.Monetary));
fprintf('Monetary中位数：%.2f\n', median(RFM.Monetary));
fprintf('==========================\n');

%% 6. RFM 五分位打分
% R: Recency越小越好
% F: Frequency越大越好
% M: Monetary越大越好
%
% 这里用排序位置打分，避免 quantile 边界重复导致 discretize 报错

RFM.R_Score = quintile_score(RFM.Recency, false);    % false: 越小越好
RFM.F_Score = quintile_score(RFM.Frequency, true);   % true: 越大越好
RFM.M_Score = quintile_score(RFM.Monetary, true);    % true: 越大越好

RFM.RFM_Score = RFM.R_Score + RFM.F_Score + RFM.M_Score;

%% 7. 基于 RFM 得分划分客户类型

RFM.CustomerSegment = strings(height(RFM), 1);

for i = 1:height(RFM)

    R = RFM.R_Score(i);
    F = RFM.F_Score(i);
    M = RFM.M_Score(i);

    if R >= 4 && F >= 4 && M >= 4
        RFM.CustomerSegment(i) = "高价值活跃客户";

    elseif R <= 2 && F >= 4 && M >= 4
        RFM.CustomerSegment(i) = "重要流失风险客户";

    elseif R >= 4 && F <= 2 && M >= 3
        RFM.CustomerSegment(i) = "近期高消费客户";

    elseif R <= 2 && F <= 2 && M <= 2
        RFM.CustomerSegment(i) = "沉睡低价值客户";

    elseif F == 1
        RFM.CustomerSegment(i) = "一次性购买客户";

    elseif R >= 4 && F >= 3
        RFM.CustomerSegment(i) = "活跃复购客户";

    elseif M >= 4
        RFM.CustomerSegment(i) = "高消费潜力客户";

    else
        RFM.CustomerSegment(i) = "一般客户";
    end
end

%% 8. 客户分层统计

[G_seg, segList] = findgroups(RFM.CustomerSegment);

segCustomerCount = splitapply(@numel, RFM.CustomerID, G_seg);
segAvgRecency = splitapply(@mean, RFM.Recency, G_seg);
segAvgFrequency = splitapply(@mean, RFM.Frequency, G_seg);
segAvgMonetary = splitapply(@mean, RFM.Monetary, G_seg);
segTotalMonetary = splitapply(@sum, RFM.Monetary, G_seg);

segmentResult = table(segList(:), segCustomerCount(:), ...
    segAvgRecency(:), segAvgFrequency(:), segAvgMonetary(:), segTotalMonetary(:), ...
    'VariableNames', {'CustomerSegment', 'CustomerCount', ...
    'AvgRecency', 'AvgFrequency', 'AvgMonetary', 'TotalMonetary'});

segmentResult.SalesShare = segmentResult.TotalMonetary / sum(segmentResult.TotalMonetary) * 100;
segmentResult = sortrows(segmentResult, 'TotalMonetary', 'descend');

disp('客户分层统计结果：');
disp(segmentResult);

%% 9. K-means 聚类准备
% 不取对数，只对原始RFM指标做标准化
% 标准化目的是消除量纲差异，不改变原始业务含义

X = [RFM.Recency, RFM.Frequency, RFM.Monetary];
Xz = zscore(X);

%% 10. Elbow Method 选择 K

maxK = 10;
SSE = zeros(maxK, 1);

rng(1);

for k = 1:maxK
    [~, ~, sumd] = kmeans(Xz, k, ...
        'Replicates', 10, ...
        'MaxIter', 1000);
    SSE(k) = sum(sumd);
end

figure('Position', [100, 100, 800, 500]);

plot(1:maxK, SSE, '-o', ...
    'LineWidth', 2, ...
    'MarkerSize', 7);

xlabel('聚类数 K', 'FontSize', 12, 'FontWeight', 'bold');
ylabel('簇内平方和 SSE', 'FontSize', 12, 'FontWeight', 'bold');
title('Elbow Method 选择K值', 'FontSize', 15, 'FontWeight', 'bold');

grid on;
box off;
set(gca, 'FontSize', 10, 'LineWidth', 1.1);

print('RFM_Elbow_Method.png', '-dpng', '-r300');

%% 11. K-means 聚类
% 根据 Elbow Method 图选择 K
% 如果你的肘部明显在3或5，可以手动改这里

k = 3;

rng(1);

clusterIdx = kmeans(Xz, k, ...
    'Replicates', 20, ...
    'MaxIter', 1000);

RFM.Cluster = clusterIdx;

%% 12. 聚类结果统计画像

[G_cluster, clusterList] = findgroups(RFM.Cluster);

clusterCount = splitapply(@numel, RFM.CustomerID, G_cluster);
clusterAvgR = splitapply(@mean, RFM.Recency, G_cluster);
clusterAvgF = splitapply(@mean, RFM.Frequency, G_cluster);
clusterAvgM = splitapply(@mean, RFM.Monetary, G_cluster);
clusterTotalM = splitapply(@sum, RFM.Monetary, G_cluster);

clusterResult = table(clusterList(:), clusterCount(:), ...
    clusterAvgR(:), clusterAvgF(:), clusterAvgM(:), clusterTotalM(:), ...
    'VariableNames', {'Cluster', 'CustomerCount', ...
    'AvgRecency', 'AvgFrequency', 'AvgMonetary', 'TotalMonetary'});

clusterResult.SalesShare = clusterResult.TotalMonetary / sum(clusterResult.TotalMonetary) * 100;

%% 13. 根据原始 RFM 均值给聚类命名

clusterResult.ClusterName = strings(height(clusterResult), 1);

medianR = median(RFM.Recency);
medianF = median(RFM.Frequency);
medianM = median(RFM.Monetary);

for i = 1:height(clusterResult)

    r = clusterResult.AvgRecency(i);
    f = clusterResult.AvgFrequency(i);
    m = clusterResult.AvgMonetary(i);

    if r <= medianR && f >= medianF && m >= medianM
        clusterResult.ClusterName(i) = "高价值活跃客户";

    elseif r > medianR && f <= medianF && m <= medianM
        clusterResult.ClusterName(i) = "沉睡低价值客户";

    elseif r > medianR && m >= medianM
        clusterResult.ClusterName(i) = "高价值流失风险客户";

    elseif r <= medianR && f <= medianF
        clusterResult.ClusterName(i) = "近期低频客户";

    elseif f >= medianF && m < medianM
        clusterResult.ClusterName(i) = "高频低额客户";

    else
        clusterResult.ClusterName(i) = "一般客户";
    end
end

clusterResult = sortrows(clusterResult, 'TotalMonetary', 'descend');

disp('K-means聚类结果画像：');
disp(clusterResult);

%% 14. 图1：聚类画像图
% 注意：Recency越高代表越久未购买，客户活跃度越低

profile = zeros(k, 3);

for c = 1:k
    profile(c, 1) = mean(Xz(RFM.Cluster == c, 1));  % Recency
    profile(c, 2) = mean(Xz(RFM.Cluster == c, 2));  % Frequency
    profile(c, 3) = mean(Xz(RFM.Cluster == c, 3));  % Monetary
end

figure('Position', [100, 100, 860, 520]);

bar(profile, 'grouped');

xlabel('客户聚类类别', 'FontSize', 12, 'FontWeight', 'bold');
ylabel('标准化均值', 'FontSize', 12, 'FontWeight', 'bold');
title('不同客户聚类的RFM画像', 'FontSize', 15, 'FontWeight', 'bold');

legend({'Recency', 'Frequency', 'Monetary'}, ...
    'Location', 'best');

grid on;
box off;
set(gca, 'FontSize', 10, 'LineWidth', 1.1);

xticks(1:k);
xticklabels("Cluster " + string(1:k));

print('RFM_Kmeans聚类画像.png', '-dpng', '-r300');

%% 15. 图2：K-means 聚类销售贡献图

clusterPlot = sortrows(clusterResult, 'SalesShare', 'ascend');

figure('Position', [100, 100, 900, 520]);

y = 1:height(clusterPlot);

b = barh(y, clusterPlot.SalesShare, 'BarWidth', 0.65);
b.FaceColor = 'flat';

cmap = parula(height(clusterPlot));
b.CData = cmap;

yticks(y);
yticklabels("Cluster " + string(clusterPlot.Cluster) + "：" + clusterPlot.ClusterName);

xlabel('销售额贡献占比 %', 'FontSize', 12, 'FontWeight', 'bold');
ylabel('客户聚类类别', 'FontSize', 12, 'FontWeight', 'bold');
title('不同聚类客户的销售额贡献', 'FontSize', 15, 'FontWeight', 'bold');

grid on;
box off;
set(gca, 'FontSize', 10, 'LineWidth', 1.1);

for i = 1:height(clusterPlot)
    text(clusterPlot.SalesShare(i) + 0.3, y(i), ...
        sprintf('%.2f%%  n=%d', ...
        clusterPlot.SalesShare(i), ...
        clusterPlot.CustomerCount(i)), ...
        'VerticalAlignment', 'middle', ...
        'FontSize', 10);
end

xlim([0, max(clusterPlot.SalesShare) * 1.2]);

print('RFM_Kmeans销售贡献.png', '-dpng', '-r300');

%% 16. 图3：客户类型销售贡献图

segmentPlot = sortrows(segmentResult, 'SalesShare', 'ascend');

figure('Position', [100, 100, 900, 520]);

y = 1:height(segmentPlot);

b = barh(y, segmentPlot.SalesShare, 'BarWidth', 0.65);
b.FaceColor = 'flat';

cmap = parula(height(segmentPlot));
b.CData = cmap;

yticks(y);
yticklabels(segmentPlot.CustomerSegment);

xlabel('销售额贡献占比 %', 'FontSize', 12, 'FontWeight', 'bold');
ylabel('客户类型', 'FontSize', 12, 'FontWeight', 'bold');
title('不同客户类型的销售额贡献', 'FontSize', 15, 'FontWeight', 'bold');

grid on;
box off;
set(gca, 'FontSize', 10, 'LineWidth', 1.1);

for i = 1:height(segmentPlot)
    text(segmentPlot.SalesShare(i) + 0.3, y(i), ...
        sprintf('%.2f%%  n=%d', ...
        segmentPlot.SalesShare(i), ...
        segmentPlot.CustomerCount(i)), ...
        'VerticalAlignment', 'middle', ...
        'FontSize', 10);
end

xlim([0, max(segmentPlot.SalesShare) * 1.2]);

print('RFM_客户类型销售贡献.png', '-dpng', '-r300');

%% 17.图4：不同客户类型数量占比饼图
segmentPie = sortrows(segmentResult, 'CustomerCount', 'descend');

figure('Position', [100, 100, 820, 600]);

labels = strings(height(segmentPie), 1);

for i = 1:height(segmentPie)
    labels(i) = sprintf('%s\n%d人', ...
        segmentPie.CustomerSegment(i), ...
        segmentPie.CustomerCount(i));
end

pie(segmentPie.CustomerCount, labels);

title('不同客户类型数量占比', ...
    'FontSize', 15, ...
    'FontWeight', 'bold');

set(gca, 'FontSize', 10);

print('RFM_客户类型数量占比饼图.png', '-dpng', '-r300');

%% 18. 保存结果

writetable(RFM, 'RFM客户明细结果.xlsx');
writetable(segmentResult, 'RFM客户分层统计.xlsx');
writetable(clusterResult, 'RFM_Kmeans聚类统计.xlsx');

save('rfm_analysis_result.mat', ...
    'RFM', 'segmentResult', 'clusterResult', ...
    'oneTimeBuyerCount', 'oneTimeBuyerRatio', 'SSE');

disp('RFM分析完成，结果已保存。');


function score = quintile_score(x, higherBetter)
% quintile_score
% 将变量按排序位置分成5档，输出1-5分
% higherBetter = true: 数值越大分数越高
% higherBetter = false: 数值越小分数越高
%
% 用排序位置而不是quantile边界，避免大量重复值导致分位点重复

    x = x(:);
    n = length(x);
    score = zeros(n, 1);

    if higherBetter
        [~, idx] = sort(x, 'ascend');
    else
        [~, idx] = sort(x, 'descend');
    end

    % idx排在后面的得分更高
    for rank = 1:n
        pos = idx(rank);
        q = ceil(rank / n * 5);

        if q < 1
            q = 1;
        elseif q > 5
            q = 5;
        end

        score(pos) = q;
    end
end