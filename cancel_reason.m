%% 1. 读取清洗数据
load('cleaned_online_retail.mat');  

%% 2. 基础处理
T_cancel = T_clean;

% 确保字段类型
T_cancel.InvoiceNo = string(T_cancel.InvoiceNo);
T_cancel.Country = string(T_cancel.Country);

% 重新确认取消标签
T_cancel.IsCancel = startsWith(T_cancel.InvoiceNo, "C") | T_cancel.Quantity < 0;

% 用绝对值衡量订单规模，避免取消订单金额为负
T_cancel.AbsQuantity = abs(T_cancel.Quantity);
T_cancel.AbsAmount = abs(T_cancel.Quantity .* T_cancel.UnitPrice);

% 时间变量
T_cancel.Month = month(T_cancel.InvoiceDate);

% 旺季标签：11月和12月
T_cancel.IsPeakSeason = ismember(T_cancel.Month, [11, 12]);

%% 3. 转换为订单级数据
% 原始数据是一行商品明细，不是一张订单
% 所以先按 InvoiceNo 聚合到订单层面

[G, invoiceList] = findgroups(T_cancel.InvoiceNo);

OrderAmount = splitapply(@sum, T_cancel.AbsAmount, G);
OrderQuantity = splitapply(@sum, T_cancel.AbsQuantity, G);
IsCancelOrder = splitapply(@max, double(T_cancel.IsCancel), G);
OrderDate = splitapply(@min, T_cancel.InvoiceDate, G);
OrderMonth = month(OrderDate);
OrderYearMonth = dateshift(OrderDate, 'start', 'month');
IsPeakSeason = ismember(OrderMonth, [11, 12]);
Country = splitapply(@(x) x(1), T_cancel.Country, G);

% CustomerID 可能缺失，单独处理
CustomerID = splitapply(@(x) x(1), T_cancel.CustomerID, G);

OrderData = table(invoiceList(:), OrderDate(:), OrderYearMonth(:), ...
    OrderAmount(:), OrderQuantity(:), ...
    logical(IsCancelOrder(:)), OrderMonth(:), logical(IsPeakSeason(:)), ...
    Country(:), CustomerID(:), ...
    'VariableNames', {'InvoiceNo', 'OrderDate', 'YearMonth', ...
    'OrderAmount', 'OrderQuantity', ...
    'IsCancel', 'Month', 'IsPeakSeason', 'Country', 'CustomerID'});

fprintf('订单总数：%d\n', height(OrderData));
fprintf('取消订单数：%d\n', sum(OrderData.IsCancel));
fprintf('总体取消率：%.2f%%\n', mean(OrderData.IsCancel) * 100);


%% ========H1：大单是否更容易被取消===========

% 按订单金额分位数分组
q1 = quantile(OrderData.OrderAmount, 0.25);
q2 = quantile(OrderData.OrderAmount, 0.50);
q3 = quantile(OrderData.OrderAmount, 0.75);

OrderData.AmountGroup = strings(height(OrderData), 1);

OrderData.AmountGroup(OrderData.OrderAmount <= q1) = "小单";
OrderData.AmountGroup(OrderData.OrderAmount > q1 & OrderData.OrderAmount <= q2) = "中低金额订单";
OrderData.AmountGroup(OrderData.OrderAmount > q2 & OrderData.OrderAmount <= q3) = "中高金额订单";
OrderData.AmountGroup(OrderData.OrderAmount > q3) = "大单";

[G_amount, amountGroupList] = findgroups(OrderData.AmountGroup);

amountCancelRate = splitapply(@mean, double(OrderData.IsCancel), G_amount);
amountOrderCount = splitapply(@numel, OrderData.InvoiceNo, G_amount);

amountResult = table(amountGroupList(:), amountOrderCount(:), amountCancelRate(:) * 100, ...
    'VariableNames', {'AmountGroup', 'OrderCount', 'CancelRatePercent'});


disp('H1：不同订单金额组的取消率');
disp(amountResult);
orderNames = ["小单", "中低金额订单", "中高金额订单", "大单"];
[~, orderIdx] = ismember(amountResult.AmountGroup, orderNames);
amountResult.OrderIndex = orderIdx;
amountResult = sortrows(amountResult, 'OrderIndex');

figure('Position', [100, 100, 820, 500]);

x = 1:height(amountResult);

b = bar(x, amountResult.CancelRatePercent, 'BarWidth', 0.6);
b.FaceColor = 'flat';

b.CData = [
    0.70 0.85 0.95
    0.45 0.70 0.88
    0.25 0.52 0.76
    0.10 0.32 0.56
];

xticks(x);
xticklabels(amountResult.AmountGroup);
xtickangle(20);

xlabel('订单金额分组', 'FontSize', 12, 'FontWeight', 'bold');
ylabel('取消率 %', 'FontSize', 12, 'FontWeight', 'bold');
title('不同订单金额组的取消率', 'FontSize', 15, 'FontWeight', 'bold');

grid on;
box off;
set(gca, 'FontSize', 10, 'LineWidth', 1.1);

ylim([0, max(amountResult.CancelRatePercent) * 1.2]);

print('H1_订单金额分组取消率.png', '-dpng', '-r300');

%% H1 卡方检验：金额组与是否取消是否有关

[amountTbl, chi2_amount, p_amount] = crosstab( ...
    categorical(OrderData.AmountGroup), ...
    OrderData.IsCancel);

fprintf('\nH1 大单取消假设检验：\n');

if p_amount < 0.0001
    fprintf('卡方统计量 = %.4f, p值 < 0.0001\n', chi2_amount);
elseif p_amount < 0.001
    fprintf('卡方统计量 = %.4f, p值 < 0.001\n', chi2_amount);
else
    fprintf('卡方统计量 = %.4f, p值 = %.4f\n', chi2_amount, p_amount);
end

% 提取大单和小单取消率
smallRate = amountResult.CancelRatePercent(amountResult.AmountGroup == "小单");
largeRate = amountResult.CancelRatePercent(amountResult.AmountGroup == "大单");

% 按取消率排序，方便观察
amountResultSorted = sortrows(amountResult, 'CancelRatePercent', 'descend');

disp('H1：订单金额分组取消率排序');
disp(amountResultSorted);

if p_amount < 0.05
    if largeRate > smallRate
        fprintf('结论：订单金额分组与取消行为显著相关，且大单取消率高于小单。\n');
        fprintf('因此，数据支持“大单更容易被取消”的假设。\n');
    elseif largeRate < smallRate
        fprintf('结论：虽然订单金额分组与取消行为显著相关，但大单取消率低于小单。\n');
        fprintf('因此，数据不支持“大单更容易被取消”的假设。\n');
    else
        fprintf('结论：订单金额分组与取消行为显著相关，但大单与小单取消率相同，需进一步检查中间组差异。\n');
    end
else
    fprintf('结论：订单金额分组与取消行为没有显著相关证据。\n');
end

% 补充判断：取消率是否随金额组递增
rateSeq = amountResult.CancelRatePercent;

if all(diff(rateSeq) >= 0)
    fprintf('补充判断：取消率随订单金额分组上升，呈现单调递增趋势。\n');
elseif largeRate > smallRate
    fprintf('补充判断：大单取消率高于小单，但中间组不完全单调递增。\n');
else
    fprintf('补充判断：未观察到订单金额越大取消率越高的稳定趋势。\n');
end
%% =======H2：新客户是否更容易取消==============

% 只分析有 CustomerID 的订单
OrderWithCustomer = OrderData(~ismissing(OrderData.CustomerID) & OrderData.CustomerID ~= "", :);

% 按客户第一次下单时间判断新老客户
T_customer_all = T_cancel(~ismissing(T_cancel.CustomerID) & T_cancel.CustomerID ~= "", :);

[Gcust, custList] = findgroups(T_customer_all.CustomerID);
FirstDate = splitapply(@min, T_customer_all.InvoiceDate, Gcust);

CustomerFirst = table(custList(:), FirstDate(:), ...
    'VariableNames', {'CustomerID', 'FirstDate'});

% 合并客户首次购买日期
OrderWithCustomer = join(OrderWithCustomer, CustomerFirst, 'Keys', 'CustomerID');

% 定义新客户：
% 如果该订单日期距离客户第一次购买日期不超过30天，视为新客户订单
OrderWithCustomer.DaysFromFirst = days(OrderWithCustomer.OrderDate - OrderWithCustomer.FirstDate);
OrderWithCustomer.IsNewCustomer = OrderWithCustomer.DaysFromFirst <= 30;

[G_new, newCustomerList] = findgroups(OrderWithCustomer.IsNewCustomer);

newCancelRate = splitapply(@mean, double(OrderWithCustomer.IsCancel), G_new);
newOrderCount = splitapply(@numel, OrderWithCustomer.InvoiceNo, G_new);

newCustomerResult = table(logical(newCustomerList(:)), newOrderCount(:), newCancelRate(:) * 100, ...
    'VariableNames', {'IsNewCustomer', 'OrderCount', 'CancelRatePercent'});

disp('H2：新客户与老客户取消率');
disp(newCustomerResult);

newCustomerResult.Label = strings(height(newCustomerResult), 1);
newCustomerResult.Label(newCustomerResult.IsNewCustomer == false) = "老客户";
newCustomerResult.Label(newCustomerResult.IsNewCustomer == true) = "新客户";

[~, sortIdx] = ismember(newCustomerResult.Label, ["老客户", "新客户"]);
newCustomerResult.SortIndex = sortIdx;
newCustomerResult = sortrows(newCustomerResult, 'SortIndex');

% 提取新客户和老客户取消率
oldRate = newCustomerResult.CancelRatePercent(newCustomerResult.IsNewCustomer == false);
newRate = newCustomerResult.CancelRatePercent(newCustomerResult.IsNewCustomer == true);

fprintf('\nH2 新客户取消假设检验：\n');
fprintf('卡方统计量 = %.4f, p值 = %.4f\n', chi2_new, p_new);

if p_new < 0.05
    if newRate > oldRate
        fprintf('结论：新老客户身份与取消行为显著相关，且新客户取消率高于老客户。\n');
        fprintf('因此，数据支持“新客户更容易取消”的假设。\n');
    elseif newRate < oldRate
        fprintf('结论：虽然根据p值新老客户身份与取消行为显著相关，但新客户取消率低于老客户。\n');
        fprintf('因此，数据不支持“新客户更容易取消”的假设。\n');
    else
        fprintf('结论：新老客户身份与取消行为显著相关，但两组取消率相同，需进一步检查数据。\n');
    end
else
    fprintf('结论：新老客户身份与取消行为没有显著相关证据。\n');
end

%% ============ H3：某些国家取消率是否更高 ===============

[G_country, countryList] = findgroups(OrderData.Country);

countryCancelRate = splitapply(@mean, double(OrderData.IsCancel), G_country) * 100;
countryOrderCount = splitapply(@numel, OrderData.InvoiceNo, G_country);
countryCancelCount = splitapply(@sum, double(OrderData.IsCancel), G_country);

countryResult = table(countryList(:), countryOrderCount(:), countryCancelCount(:), ...
    countryCancelRate(:), ...
    'VariableNames', {'Country', 'OrderCount', 'CancelCount', 'CancelRatePercent'});

% 过滤订单数太少的国家，避免小样本误导
minOrderThreshold = 30;
countryResult = countryResult(countryResult.OrderCount >= minOrderThreshold, :);

% 按取消率从高到低排序
countryResult = sortrows(countryResult, 'CancelRatePercent', 'descend');

disp('H3：各国家取消率，已过滤订单数少于30的国家，并按取消率降序排列');
disp(countryResult);

%Top10 高取消率国家
topN = min(10, height(countryResult));
topCountry = countryResult(1:topN, :);

% 确保按取消率从高到低排序
topCountry = sortrows(topCountry, 'CancelRatePercent', 'descend');

figure('Position', [100, 100, 950, 540]);

y = 1:topN;

b = barh(y, topCountry.CancelRatePercent, 'BarWidth', 0.65);
b.FaceColor = 'flat';

% 颜色：取消率越高颜色越深
cmap = flipud(autumn(topN));
b.CData = cmap;

% y轴标签
yticks(y);
yticklabels(topCountry.Country);

% 让取消率最高的国家显示在最上方
set(gca, 'YDir', 'reverse');

xlabel('取消率 %', 'FontSize', 12, 'FontWeight', 'bold');
ylabel('国家', 'FontSize', 12, 'FontWeight', 'bold');
title('取消率最高的国家 Top 10', 'FontSize', 15, 'FontWeight', 'bold');

grid on;
box off;
set(gca, 'FontSize', 10, 'LineWidth', 1.1);

% 数值标注：取消率 + 订单数
for i = 1:topN
    text(topCountry.CancelRatePercent(i) + 0.4, y(i), ...
        sprintf('%.2f%%  n=%d', ...
        topCountry.CancelRatePercent(i), ...
        topCountry.OrderCount(i)), ...
        'VerticalAlignment', 'middle', ...
        'FontSize', 10);
end

xlim([0, max(topCountry.CancelRatePercent) * 1.25]);

print('H3_国家取消率Top10.png', '-dpng', '-r300');

%% 卡方检验：国家与是否取消是否有关

validCountries = countryResult.Country;
OrderCountryTest = OrderData(ismember(OrderData.Country, validCountries), :);

[countryTbl, chi2_country, p_country] = crosstab( ...
    categorical(OrderCountryTest.Country), ...
    OrderCountryTest.IsCancel);

fprintf('\nH3 国家取消率差异检验：\n');

if p_country < 0.0001
    fprintf('卡方统计量 = %.4f, p值 < 0.0001\n', chi2_country);
elseif p_country < 0.001
    fprintf('卡方统计量 = %.4f, p值 < 0.001\n', chi2_country);
else
    fprintf('卡方统计量 = %.4f, p值 = %.4f\n', chi2_country, p_country);
end

if p_country < 0.05
    fprintf('结论：不同国家之间取消率存在显著差异。\n');
    fprintf('进一步观察Top10结果，可识别取消风险较高的国家市场。\n');
else
    fprintf('结论：没有证据表明不同国家之间取消率存在显著差异。\n');
end


%% ======= H4：旺季 11-12 月取消率是否更高 =============

% 以月份为单位统计订单数、取消订单数、未取消订单数、取消率
[G_month, monthList] = findgroups(OrderData.YearMonth);

monthOrderCount = splitapply(@numel, OrderData.InvoiceNo, G_month);
monthCancelCount = splitapply(@sum, double(OrderData.IsCancel), G_month);
monthNotCancelCount = monthOrderCount - monthCancelCount;
monthCancelRate = monthCancelCount ./ monthOrderCount * 100;

monthResult = table(monthList(:), monthOrderCount(:), monthCancelCount(:), ...
    monthNotCancelCount(:), monthCancelRate(:), ...
    'VariableNames', {'YearMonth', 'OrderCount', 'CancelCount', ...
    'NotCancelCount', 'CancelRatePercent'});

monthResult.IsPeakSeason = ismember(month(monthResult.YearMonth), [9, 10, 11]);

disp('H4：月度取消率与订单结构');
disp(monthResult);

%%旺季与非旺季统计检验

isPeak = OrderData.IsPeakSeason;
isCancel = OrderData.IsCancel;

n_nonpeak = sum(~isPeak);
n_peak = sum(isPeak);

cancel_nonpeak = sum(isCancel(~isPeak));
cancel_peak = sum(isCancel(isPeak));

rate_nonpeak = cancel_nonpeak / n_nonpeak * 100;
rate_peak = cancel_peak / n_peak * 100;

peakResult = table( ...
    ["非旺季"; "旺季"], ...
    [n_nonpeak; n_peak], ...
    [cancel_nonpeak; cancel_peak], ...
    [rate_nonpeak; rate_peak], ...
    'VariableNames', {'SeasonType', 'OrderCount', 'CancelCount', 'CancelRatePercent'});

disp('H4：旺季与非旺季取消率');
disp(peakResult);

[peakTbl, chi2_peak, p_peak] = crosstab(OrderData.IsPeakSeason, OrderData.IsCancel);

fprintf('\nH4 旺季取消假设检验：\n');
fprintf('卡方统计量 = %.4f, p值 = %.4f\n', chi2_peak, p_peak);

if p_peak < 0.05
    if rate_peak > rate_nonpeak
        fprintf('结论：旺季与取消行为显著相关，且旺季取消率高于非旺季。\n');
    elseif rate_peak < rate_nonpeak
        fprintf('结论：旺季与取消行为显著相关，但旺季取消率低于非旺季。\n');
        fprintf('因此，数据不支持“旺季取消率更高”的假设。\n');
    else
        fprintf('结论：旺季与取消行为显著相关，但两组取消率数值相同，需进一步检查数据。\n');
    end
else
    fprintf('结论：旺季与取消行为没有显著相关证据。\n');
end
OrderData.IsPeakSeason = ismember(month(OrderData.OrderDate), [9, 10, 11]);

%% 1. 按月份统计订单结构与取消率

[G_month, monthList] = findgroups(OrderData.YearMonth);

monthOrderCount = splitapply(@numel, OrderData.InvoiceNo, G_month);
monthCancelCount = splitapply(@sum, double(OrderData.IsCancel), G_month);
monthNotCancelCount = monthOrderCount - monthCancelCount;
monthCancelRate = monthCancelCount ./ monthOrderCount * 100;

monthResult = table(monthList(:), monthOrderCount(:), monthCancelCount(:), ...
    monthNotCancelCount(:), monthCancelRate(:), ...
    'VariableNames', {'YearMonth', 'OrderCount', 'CancelCount', ...
    'NotCancelCount', 'CancelRatePercent'});

monthResult.IsPeakSeason = ismember(month(monthResult.YearMonth), [9, 10, 11]);

disp('H4：月度订单结构与取消率');
disp(monthResult);

%% 2. 基于“月度取消率”比较淡旺季，而不是直接比较订单总数

offSeasonMonths = monthResult(~monthResult.IsPeakSeason, :);
peakSeasonMonths = monthResult(monthResult.IsPeakSeason, :);

offSeasonMeanRate = mean(offSeasonMonths.CancelRatePercent);
peakSeasonMeanRate = mean(peakSeasonMonths.CancelRatePercent);

fprintf('\nH4：基于月度取消率的淡旺季比较\n');
fprintf('淡季月份平均取消率：%.2f%%，月份数=%d\n', ...
    offSeasonMeanRate, height(offSeasonMonths));
fprintf('旺季月份平均取消率：%.2f%%，月份数=%d\n', ...
    peakSeasonMeanRate, height(peakSeasonMonths));

if peakSeasonMeanRate > offSeasonMeanRate
    fprintf('结论：从月度平均取消率看，旺季高于淡季。\n');
else
    fprintf('结论：从月度平均取消率看，旺季不高于淡季。\n');
end


figure('Position', [100, 100, 1100, 580]);

months = monthResult.YearMonth;
normalOrders = monthResult.NotCancelCount;
cancelOrders = monthResult.CancelCount;
totalOrders = monthResult.OrderCount;
cancelRate = monthResult.CancelRatePercent;

% ================= 左轴：订单结构 =================
yyaxis left;
hold on;

yMaxLeft = max(totalOrders) * 1.15;

% 旺季背景高亮：9-11月
peakMonths = monthResult.YearMonth(monthResult.IsPeakSeason);

for i = 1:length(peakMonths)
    x1 = peakMonths(i);
    x2 = x1 + calmonths(1);

    patch([x1 x2 x2 x1], ...
          [0 0 yMaxLeft yMaxLeft], ...
          [1.00 0.92 0.78], ...
          'FaceAlpha', 0.35, ...
          'EdgeColor', 'none');
end

% 堆积面积图
Y_area = [normalOrders, cancelOrders];

hArea = area(months, Y_area, 'LineWidth', 1.0);

% 配色：正常订单蓝色，取消订单橙红色
hArea(1).FaceColor = [0.36 0.65 0.85];
hArea(1).FaceAlpha = 0.55;
hArea(1).EdgeColor = [0.25 0.50 0.70];

hArea(2).FaceColor = [0.93 0.55 0.42];
hArea(2).FaceAlpha = 0.75;
hArea(2).EdgeColor = [0.75 0.35 0.25];

ylabel('每月订单数', 'FontSize', 12, 'FontWeight', 'bold');
ylim([0, yMaxLeft]);
set(gca, 'YColor', [0.20 0.20 0.20]);

% ================= 右轴：取消率折线 =================
yyaxis right;

hLine = plot(months, cancelRate, '-o', ...
    'LineWidth', 3.0, ...
    'MarkerSize', 7, ...
    'MarkerFaceColor', [0.82 0.18 0.15], ...
    'MarkerEdgeColor', 'w', ...
    'Color', [0.82 0.18 0.15]);

% 高亮旺季月份取消率点
peakRows = monthResult.IsPeakSeason;

scatter(months(peakRows), cancelRate(peakRows), ...
    95, ...
    'filled', ...
    'MarkerFaceColor', [0.82 0.18 0.15], ...
    'MarkerEdgeColor', 'k');

% 淡季、旺季月均取消率参考线
hOff = yline(offSeasonMeanRate, '--', ...
    sprintf('淡季月均 %.2f%%', offSeasonMeanRate), ...
    'Color', [0.25 0.45 0.70], ...
    'LineWidth', 1.4);

hPeak = yline(peakSeasonMeanRate, '--', ...
    sprintf('旺季月均 %.2f%%', peakSeasonMeanRate), ...
    'Color', [0.82 0.18 0.15], ...
    'LineWidth', 1.4);

ylabel('月度取消率 %', 'FontSize', 12, 'FontWeight', 'bold');
set(gca, 'YColor', [0.82 0.18 0.15]);

rateMin = min(cancelRate);
rateMax = max(cancelRate);
ylim([rateMin - 1.2, rateMax + 1.5]);

% 标注最高取消率月份
[~, maxIdx] = max(cancelRate);

text(months(maxIdx), cancelRate(maxIdx) + 0.35, ...
    sprintf('最高 %.2f%%', cancelRate(maxIdx)), ...
    'HorizontalAlignment', 'center', ...
    'FontSize', 10, ...
    'Color', [0.82 0.18 0.15], ...
    'FontWeight', 'bold');

xlabel('月份', 'FontSize', 12, 'FontWeight', 'bold');
title('月度订单结构与取消率变化', ...
    'FontSize', 15, ...
    'FontWeight', 'bold');

grid on;
box off;

xlim([datetime(2010,12,1), datetime(2011,12,9)]);
xticks(datetime(2010,12,1):calmonths(1):datetime(2011,12,1));
xtickformat('yyyy年M月');
xtickangle(45);

set(gca, 'FontSize', 10, 'LineWidth', 1.1);

% 图例
legend([hArea(1), hArea(2), hLine], ...
    {'未取消订单', '取消订单', '月度取消率'}, ...
    'Location', 'northwest');

hold off;

% 导出高清图
print('H4_月度订单结构与取消率变化.png', '-dpng', '-r300');


%% 5. 保存结果
writetable(amountResult, 'H1_订单金额分组取消率.xlsx');
writetable(newCustomerResult, 'H2_新老客户取消率.xlsx');
writetable(countryResult, 'H3_国家取消率.xlsx');
writetable(peakResult, 'H4_旺季取消率.xlsx');

save('cancel_reason_test_result.mat', ...
    'OrderData', 'amountResult', 'newCustomerResult', ...
    'countryResult', 'peakResult', ...
    'p_amount', 'p_new', 'p_country', 'p_peak');

disp('取消原因假设验证完成。');