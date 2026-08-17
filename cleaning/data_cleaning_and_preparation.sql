--- This script is used to prepare the respective views which will be used for the final analysis

-- Making the sellers information available
CREATE VIEW sellers AS
SELECT 
    seller_id,
    seller_city,
    seller_state
FROM dbo.olist_sellers;
GO

-- Preparing the payments table
CREATE VIEW payments AS
SELECT 
    order_id, 
    COUNT(DISTINCT(payment_type)) AS payment_type,
    MAX(payment_installments) AS payment_installments,
    SUM(ROUND(payment_value,2)) AS payment_value
FROM dbo.olist_order_payments
WHERE payment_type != 'not_defined'
GROUP BY order_id;
GO

-- Cleaning for the Orders table
CREATE VIEW orders AS 

SELECT 
	order_id,
	customer_id,
	order_status,
	CAST(order_purchase_timestamp AS DATE) AS purchase_date,
	CAST(order_approved_at AS DATE) AS approval_date,
	CAST(order_delivered_customer_date AS DATE) AS delivery_date,
	CAST(order_delivered_carrier_date AS DATE) AS carrier_date,
	CAST(order_estimated_delivery_date AS DATE) AS estimated_delivery_date,
	CASE 
			WHEN order_delivered_customer_date > order_estimated_delivery_date THEN 'Late delivery'
			ELSE 'Prompt delivery'
			END AS delivery_checks,
	DATEDIFF(DAY, order_purchase_timestamp, order_delivered_customer_date) AS order_delivered_in_days
FROM dbo.olist_orders
WHERE order_status = 'delivered' AND order_delivered_customer_date IS NOT NULL;
GO

-- Cleaning and aggregation for products and order items table
CREATE VIEW order_items AS
SELECT 
    ooi.order_id,
    ooi.order_item_id,
    ooi.seller_id, 
    ooi.product_id,
    COALESCE(nt.column2, 'Unspecified') AS product_category_name, 
    ROUND(ooi.price,2) price, 
    ROUND(ooi.freight_value,2) freight_value
FROM 
    dbo.olist_order_items AS ooi
LEFT JOIN 
    dbo.olist_products AS op
ON 
    op.product_id = ooi.product_id 
LEFT JOIN
    dbo.product_category_name_translation AS nt
ON 
    nt.column1 = op.product_category_name;
GO

-- Making the customers information available
CREATE VIEW customers AS 
SELECT 
    customer_id, 
    customer_unique_id, 
    customer_city, 
    customer_state
FROM dbo.olist_customers

GO;
