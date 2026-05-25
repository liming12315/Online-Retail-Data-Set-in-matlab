clear; clc; close all;

%% 1. 读取 Excel 数据
filename = 'Retail Exercise.xlsx';

opts = detectImportOptions(filename);
opts.VariableNamingRule = 'preserve';
opts = setvartype(opts, 'InvoiceNo', 'char');
opts = setvartype(opts, 'StockCode', 'char');
opts = setvartype(opts, 'Description', 'char');
opts = setvartype(opts, 'Country', 'char');
opts = setvartype(opts, 'CustomerID', 'char');
T = readtable(filename, opts);

disp('原始字段名：');
disp(T.Properties.VariableNames);

%% 2. 统一字段类型
T.InvoiceNo = string(T.InvoiceNo);
T.StockCode = string(T.StockCode);
T.Description = string(T.Description);
T.Country = string(T.Country);
T.CustomerID = string(T.CustomerID);
% 日期处理
T.InvoiceDate = datetime(T.InvoiceDate, ...
    'InputFormat', 'yyyy/M/d H:mm');

% 限定分析区间：2010/12/1 到 2011/12/9
startDate = datetime(2010,12,1,0,0,0);
endDate   = datetime(2011,12,9,23,59,59);

T = T(T.InvoiceDate >= startDate & T.InvoiceDate <= endDate, :);

fprintf('筛选后最早日期：%s\n', datestr(min(T.InvoiceDate)));
fprintf('筛选后最晚日期：%s\n', datestr(max(T.InvoiceDate)));
fprintf('筛选后记录数：%d\n', height(T));

%% 3. 构造基础变量
T.SalesAmount = T.Quantity .* T.UnitPrice;

% 判断取消订单
T.IsCancel = startsWith(T.InvoiceNo, "C") | T.Quantity < 0;
fprintf('原始数据中识别到的取消记录数：%d\n', sum(T.IsCancel));
fprintf('InvoiceNo 以 C 开头的记录数：%d\n', sum(startsWith(T.InvoiceNo, "C")));
fprintf('Quantity < 0 的记录数：%d\n', sum(T.Quantity < 0));

% 时间变量
T.Date = dateshift(T.InvoiceDate, 'start', 'day');
T.YearMonth = dateshift(T.InvoiceDate, 'start', 'month');
T.Year = year(T.InvoiceDate);
T.Month = month(T.InvoiceDate);
T.Weekday = weekday(T.InvoiceDate);
T.Hour = hour(T.InvoiceDate);

%% 4. 基础清洗
% 去掉单价小于等于0的异常记录
T_clean = T(T.UnitPrice > 0, :);

% 正常销售记录
T_sales = T_clean(~T_clean.IsCancel & T_clean.Quantity > 0, :);
fprintf('\n====== 清洗结果 ======\n');
fprintf('原始记录数：%d\n', height(T));
fprintf('清洗后记录数：%d\n', height(T_clean));
fprintf('正常销售记录数：%d\n', height(T_sales));
fprintf('取消/退货记录数：%d\n', sum(T_clean.IsCancel));
fprintf('======================\n');

%% 5. 月度销售额
monthlySales = groupsummary(T_sales, 'YearMonth', 'sum', 'SalesAmount');

figure;
plot(monthlySales.YearMonth, monthlySales.sum_SalesAmount, '-o', 'LineWidth', 1.5);
xlabel('月份');
ylabel('销售额');
title('月度销售额趋势');
grid on;

xlim([startDate endDate]);
xticks(datetime(2010,12,1):calmonths(1):datetime(2011,12,1));
xtickformat('yyyy年M月');

%% 6. 每日订单数变化趋势：补全无交易日期
%% 每日订单数变化趋势：原始值 + 7日/30日移动平均

[G, d] = findgroups(T_sales.Date);
dailyOrderCount = splitapply(@(x) numel(unique(x)), T_sales.InvoiceNo, G);

dailyOrders = table(d(:), dailyOrderCount(:), ...
    'VariableNames', {'Date', 'OrderCount'});

startDate = datetime(2010,12,1);
endDate   = datetime(2011,12,9);

% 补全所有日期，没有交易的日期记为0
allDates = (startDate:endDate)';
fullDailyOrders = table(allDates, zeros(length(allDates),1), ...
    'VariableNames', {'Date', 'OrderCount'});

[tf, loc] = ismember(fullDailyOrders.Date, dailyOrders.Date);
fullDailyOrders.OrderCount(tf) = dailyOrders.OrderCount(loc(tf));

% 移动平均
fullDailyOrders.MA7 = movmean(fullDailyOrders.OrderCount, 7);
fullDailyOrders.MA30 = movmean(fullDailyOrders.OrderCount, 30);

figure;
plot(fullDailyOrders.Date, fullDailyOrders.OrderCount, ':', 'LineWidth', 0.8);
hold on;
plot(fullDailyOrders.Date, fullDailyOrders.MA7, 'LineWidth', 1.5);
plot(fullDailyOrders.Date, fullDailyOrders.MA30, 'LineWidth', 2);
hold off;

xlabel('日期');
ylabel('每日订单数');
title('每日订单变化趋势及移动平均');
legend('每日订单数', '7日移动平均', '30日移动平均', 'Location', 'best');
grid on;

xlim([startDate endDate]);
xticks(datetime(2010,12,1):calmonths(1):datetime(2011,12,1));
xtickformat('yyyy年M月');

%% 7. 每日销售额趋势
%% 每日销售额趋势：原始值 + 7日/30日移动平均

dailySales = groupsummary(T_sales, 'Date', 'sum', 'SalesAmount');

startDate = datetime(2010,12,1);
endDate   = datetime(2011,12,9);

% 补全所有日期
allDates = (startDate:endDate)';
fullDailySales = table(allDates, zeros(length(allDates),1), ...
    'VariableNames', {'Date', 'SalesAmount'});

[tf, loc] = ismember(fullDailySales.Date, dailySales.Date);
fullDailySales.SalesAmount(tf) = dailySales.sum_SalesAmount(loc(tf));

% 移动平均
fullDailySales.MA7 = movmean(fullDailySales.SalesAmount, 7);
fullDailySales.MA30 = movmean(fullDailySales.SalesAmount, 30);

figure;
plot(fullDailySales.Date, fullDailySales.SalesAmount, ':', 'LineWidth', 0.8);
hold on;
plot(fullDailySales.Date, fullDailySales.MA7, 'LineWidth', 1.5);
plot(fullDailySales.Date, fullDailySales.MA30, 'LineWidth', 2);
hold off;

xlabel('日期');
ylabel('每日销售额');
title('每日销售额趋势及移动平均');
legend('每日销售额', '7日移动平均', '30日移动平均', 'Location', 'best');
grid on;

xlim([startDate endDate]);
xticks(datetime(2010,12,1):calmonths(1):datetime(2011,12,1));
xtickformat('yyyy年M月');

%% 8. 核心经营指标
totalSales = sum(T_sales.SalesAmount);
cancelAmount = sum(abs(T_clean.SalesAmount(T_clean.IsCancel)));
cancelCountRate = sum(T_clean.IsCancel) / height(T_clean);
cancelAmountRate = cancelAmount / (totalSales + cancelAmount);

fprintf('\n====== 核心经营指标 ======\n');
fprintf('正常销售额：%.2f\n', totalSales);
fprintf('取消/退货金额绝对值：%.2f\n', cancelAmount);
fprintf('取消记录占比：%.2f%%\n', cancelCountRate * 100);
fprintf('取消金额占比：%.2f%%\n', cancelAmountRate * 100);
fprintf('==========================\n');

%% 9. 保存清洗后的数据，供后续模型使用
save('cleaned_online_retail.mat', 'T', 'T_clean', 'T_sales');
disp('第一阶段完成：清洗数据已保存为 cleaned_online_retail.mat');