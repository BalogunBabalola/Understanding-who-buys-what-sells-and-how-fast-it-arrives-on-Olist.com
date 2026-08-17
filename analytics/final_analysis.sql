-- Which customers consistently buy a broad product mix vs. single-category buyers?
CREATE VIEW product_category_mix AS
WITH category_profile AS (
    SELECT 
        c.customer_unique_id, 
        COUNT(DISTINCT i.product_category_name) AS distinct_categories,
        COUNT(DISTINCT o.order_id) AS total_orders,
        COUNT(i.order_item_id) AS total_items_purchased,
        SUM(i.price) AS total_revenue
    FROM dbo.customers AS c
    LEFT JOIN dbo.orders AS o 
    ON c.customer_id = o.customer_id
    LEFT JOIN dbo.order_items AS i
    ON i.order_id = o.order_id
    GROUP BY c.customer_unique_id
),
segmented AS 
(
SELECT 
    customer_unique_id, total_orders,total_revenue,total_items_purchased,distinct_categories,
    CASE    
        WHEN distinct_categories = 1 THEN 'Single_category_buyer'
        WHEN distinct_categories <=3 THEN 'Narrow_buyers'
        WHEN distinct_categories <= 5  THEN 'Moderate_buyers'
        ELSE 'Broad_buyers'
        END AS buyers_segment
FROM category_profile
WHERE distinct_categories > 0
)

SELECT 
    buyers_segment,
    COUNT(customer_unique_id) AS total_customers,
    ROUND(AVG(total_orders),1) AS average_orders,
    ROUND(AVG(distinct_categories), 1) AS average_categories,
    ROUND(SUM(total_revenue),1) AS category_revenue
    FROM segmented
    GROUP BY buyers_segment;

    GO

-- What does the purchase frequency distribution look like across the customer base?
CREATE VIEW purchase_frequency AS
WITH category_profile AS (
    SELECT 
        c.customer_unique_id,
        COUNT(o.order_id) AS purchase_frequency,
        ROUND(SUM(i.price),2) AS total_spend
    FROM dbo.customers AS c
    LEFT JOIN dbo.orders AS o 
    ON c.customer_id = o.customer_id
    LEFT JOIN dbo.order_items AS i 
    ON i.order_id = o.order_id
    GROUP BY c.customer_unique_id
)

, purchase_agg AS (
SELECT 
    purchase_frequency, 
    COUNT(customer_unique_id) AS [number of customers], 
    ROUND(SUM(total_spend),2) AS [total revenue earned], ROUND(AVG(total_spend), 2) AS [average amount spent per customer]
FROM category_profile 
WHERE purchase_frequency > 0
GROUP BY purchase_frequency
)

SELECT 
    CASE 
        WHEN purchase_frequency BETWEEN 1 AND 2 THEN '1-2'
        WHEN purchase_frequency BETWEEN 3 AND 5 THEN '3-5'
        WHEN purchase_frequency BETWEEN 6 AND 9 THEN '6-9'
        WHEN purchase_frequency BETWEEN 10 AND 12 THEN '10-12'
        WHEN purchase_frequency BETWEEN 13 AND 14 THEN '13-14'
        WHEN purchase_frequency >= 15 THEN '15+'
        END AS purchase_frequency,
    SUM([number of customers]) AS total_customers,
    SUM([total revenue earned]) AS total_revenue_earned,
    ROUND(SUM([total revenue earned])/SUM([number of customers]),2) AS average_amount_spent_by_customers
FROM purchase_agg
GROUP BY
    CASE 
        WHEN purchase_frequency BETWEEN 1 AND 2 THEN '1-2'
        WHEN purchase_frequency BETWEEN 3 AND 5 THEN '3-5'
        WHEN purchase_frequency BETWEEN 6 AND 9 THEN '6-9'
        WHEN purchase_frequency BETWEEN 10 AND 12 THEN '10-12'
        WHEN purchase_frequency BETWEEN 13 AND 14 THEN '13-14'
        WHEN purchase_frequency >= 15 THEN '15+'
        END;

GO
-- Which customers have not placed an order in the last 60/90 days? (Churn detection)
CREATE VIEW churn_detection AS
WITH churn_in_days AS
(SELECT 
    c.customer_unique_id,
    MAX(purchase_date) AS last_purchase_date,
    DATEDIFF(DAY,MAX(purchase_date),'2018-08-29') AS days_since_last_purchase
FROM dbo.orders AS o
JOIN dbo.customers AS c
ON c.customer_id = o.customer_id
GROUP BY c.customer_unique_id
)

,churn_category AS (
    SELECT 
    customer_unique_id, last_purchase_date,days_since_last_purchase,
    CASE    WHEN days_since_last_purchase >= 60 THEN 'At risk'
            WHEN days_since_last_purchase >= 90 THEN 'Churned'
            ELSE 'Active'
            END AS churn_status
FROM churn_in_days
)

SELECT churn_status, COUNT(customer_unique_id) AS number_of_customers
FROM churn_category
GROUP BY churn_status;

GO

-- Which products have shown consistent volume decline over the last 3–4 periods?
CREATE VIEW product_decline_per_quarter AS
WITH quarterly_volume AS(
SELECT
    DATEPART(YEAR,o.purchase_date) AS year,
    DATEPART(QUARTER,o.purchase_date) AS quarter,
    i.product_category_name,
    COUNT(i.order_id) AS order_volume
FROM dbo.order_items AS i
JOIN dbo.orders AS o
ON o.order_id = i.order_id
WHERE 
    i.product_category_name != 'Unspecified'
GROUP BY 
     DATEPART(YEAR,o.purchase_date),
    DATEPART(QUARTER,o.purchase_date),
    i.product_category_name
),

lag_period AS(
SELECT 
    year,quarter, 
    product_category_name, order_volume,
    LAG(order_volume,1,0) OVER(PARTITION BY product_category_name ORDER BY year, quarter) AS previous_period_volume
FROM quarterly_volume
),

declining_period AS(
SELECT 
    year, quarter, product_category_name, COUNT(*) AS declining_period
FROM lag_period
WHERE order_volume < previous_period_volume
GROUP BY year,quarter,product_category_name
)

SELECT 
    l.product_category_name, l.year,
    l.quarter,l.order_volume,
    l.previous_period_volume,
    l.order_volume - l.previous_period_volume AS volume_change,
    d.declining_period,
    CASE 
        WHEN previous_period_volume = 0 THEN 'First Period'
        WHEN order_volume > previous_period_volume THEN 'Growing'
        WHEN order_volume < previous_period_volume THEN 'Declining'
        ELSE 'Flat'
    END AS period_trend
    
FROM lag_period AS l
JOIN declining_period AS d 
ON l.product_category_name = d.product_category_name
WHERE d.declining_period > 1;

GO

-- Where does revenue growth come from — price increases or volume growth?
CREATE VIEW revenue_growth_source AS
WITH quarterly_report AS (
SELECT 
    DATEPART(YEAR, o.purchase_date) AS year,
    DATEPART(QUARTER, o.purchase_date) AS quarter, 
    ROUND(SUM(oi.price),2) AS total_revenue,
    COUNT(oi.order_id) AS order_volume,
    ROUND(SUM(oi.price) / COUNT(oi.order_id),2) AS average_price
FROM dbo.order_items AS oi
JOIN dbo.orders AS o
ON o.order_id = oi.order_id
GROUP BY 
    DATEPART(YEAR, o.purchase_date),
    DATEPART(QUARTER, o.purchase_date)

)
,quarterly_with_lag AS (
SELECT *,
    LAG(total_revenue,1) OVER(ORDER BY year, quarter) AS last_quarter_revenue,
    LAG(order_volume) OVER(ORDER BY year, quarter) AS last_quarter_volume,
    LAG(average_price) OVER(ORDER BY year, quarter) AS last_quarter_average_price
FROM quarterly_report
)

SELECT 
    year, quarter,total_revenue, last_quarter_revenue,order_volume, last_quarter_volume, average_price, last_quarter_average_price,
    CASE 
        WHEN last_quarter_revenue IS NULL THEN 'First period'
        WHEN total_revenue > last_quarter_revenue AND average_price > last_quarter_average_price AND order_volume < last_quarter_volume
            THEN 'Revenue growth comes from price increase only'
        WHEN total_revenue > last_quarter_revenue AND order_volume > last_quarter_volume AND average_price < last_quarter_average_price
            THEN 'Revenue growth comes from volume increase only'
        WHEN total_revenue > last_quarter_revenue AND average_price > last_quarter_average_price AND order_volume > last_quarter_volume 
            THEN 'Revenue growth comes from both price increase and volume increase'
        WHEN total_revenue < last_quarter_revenue 
            THEN 'Revenue declined'
        WHEN total_revenue > last_quarter_revenue AND order_volume > last_quarter_volume AND average_price <= last_quarter_average_price
            THEN 'Revenue growth comes from volume increase only'
    END AS revenue_growth_remarks
FROM quarterly_with_lag;

GO

-- Which sellers are growing their order volume and which are losing it?
CREATE VIEW volume_trend AS 
WITH count_per_customer AS(
SELECT 
    s.seller_id,DATEPART(YEAR,o.purchase_date) AS year,DATEPART(QUARTER,o.purchase_date) AS quarters,COUNT(DISTINCT o.customer_id) AS customers
FROM sellers AS s
JOIN dbo.order_items AS oi
ON s.seller_id = oi.seller_id
JOIN dbo.orders AS o
ON oi.order_id = o.order_id
GROUP BY s.seller_id,DATEPART(YEAR,o.purchase_date),DATEPART(QUARTER,o.purchase_date)
)
,count_with_prev_quarter AS (
SELECT 
    seller_id, year, quarters, 
    customers,LAG(customers,1,0) OVER(PARTITION BY seller_id ORDER BY year, quarters) AS [previous quarter customers]
FROM count_per_customer
)
,count_with_trend AS(
SELECT 
    seller_id, year, quarters, customers, [previous quarter customers],
    CASE 
        WHEN customers > [previous quarter customers] THEN 1
        WHEN customers < [previous quarter customers] THEN -1
        ELSE 0
        END AS period_trend
FROM count_with_prev_quarter
)

,count_with_class AS(
SELECT
    seller_id,
    CASE
        WHEN MIN(period_trend) = -1 THEN 'Consistently Declining'
        WHEN MAX(period_trend) = 1  THEN 'Consistently Growing'
        ELSE 'Volatile'
    END AS [volume trend]
FROM (
    SELECT
    seller_id,
    period_trend,
    ROW_NUMBER() OVER (PARTITION BY seller_id ORDER BY year DESC, quarters DESC) AS recency_rank
    FROM count_with_trend
) AS recent_periods
WHERE recency_rank <= 3
GROUP BY seller_id
)

SELECT [volume trend], COUNT(seller_id) AS [number of sellers]
FROM count_with_class
GROUP BY [volume trend];

GO

-- What is the average order-to-delivery time by state?
CREATE VIEW order_to_delivery_in_days AS
SELECT 
    c.customer_state, 
    AVG(o.order_delivered_in_days) AS [order delivered in days],
    COUNT(DISTINCT c.customer_unique_id) AS total_customers,COUNT(DISTINCT s.seller_id) AS total_sellers,
    ROUND(COUNT(DISTINCT c.customer_unique_id)/ COUNT(DISTINCT s.seller_id), 1) AS sellers_per_customer
FROM dbo.customers AS c
JOIN dbo.orders AS o 
ON o.customer_id = c.customer_id
JOIN dbo.order_items AS oi
ON oi.order_id = o.order_id
JOIN dbo.sellers AS s
ON s.seller_id = oi.seller_id
GROUP BY c.customer_state;

GO