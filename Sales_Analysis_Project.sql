
--===========================================================================================  
--                            [Changes Over Time Analysis]
--===========================================================================================  
--Analyze sales performance over time

SELECT 
	DATETRUNC(month,order_date) as order_date,
	SUM(sales_amount) as total_sales,
	SUM(quantity) as total_quantity,
	COUNT(DISTINCT customer_key) as total_customers
FROM fact_sales
WHERE order_date IS NOT NULL
GROUP BY DATETRUNC(month,order_date)
ORDER BY DATETRUNC(month,order_date);

--===========================================================================================
--                           [Cummulative Analysis]
--===========================================================================================  
--Calculate the Total Sales per Month
--and the running total of sales over time

SELECT 
	order_date,
	total_sales,
	SUM(total_sales) OVER (ORDER BY order_date) as running_total,
	AVG(total_sales) OVER (ORDER BY order_date) as mov_avg
FROM(
	SELECT 
		DATETRUNC(month,order_date) as order_date,
		SUM(sales_amount) as total_sales,
		AVG(sales_amount) as avg_sales
	from fact_sales
	WHERE order_date IS NOT NULL
	GROUP BY DATETRUNC(month,order_date)
	)t
;
--===========================================================================================
--                             [Performance Analysis]
--===========================================================================================  
--Analyze the yearly performance of products by comparing each products sales 
--to both its average sales performance and the previous years sales

WITH yearly_product_sales AS
(
	SELECT 
		YEAR(f.order_date) as order_year,
		p.product_name,
		SUM(f.sales_amount) as current_sales
	FROM fact_sales f
	LEFT JOIN dim_products p
		on f.product_key = p.product_key
	WHERE f.order_date IS NOT NULL
	GROUP BY YEAR(f.order_date), p.product_name
)
SELECT 
	order_year,
	product_name,
	current_sales,
	AVG(current_sales) OVER (PARTITION BY product_name) as avg_sales,
	current_sales - AVG(current_sales) OVER(PARTITION BY product_name) as diff_avg,
	CASE 
		WHEN current_sales - AVG(current_sales) OVER(PARTITION BY product_name) > 0 THEN 'Above Avg'
		WHEN current_sales - AVG(current_sales) OVER(PARTITION BY product_name) < 0 THEN 'Below Avg'
	 Else 'Avg'
	END as avg_change,
-- Year-over-Year Analysis
	LAG(current_sales) OVER (PARTITION BY product_name ORDER BY order_year) as previous_sales,
	CASE 
		WHEN current_sales - LAG(current_sales) OVER (PARTITION BY product_name ORDER BY order_year) > 0 THEN 'Increasing'
		WHEN current_sales - LAG(current_sales) OVER (PARTITION BY product_name ORDER BY order_year) < 0 THEN 'Decreasing'
	 Else 'No Change'
	END as pre_change
FROM yearly_product_sales;


--===========================================================================================
--                          [Part-To-Whole Analysis]
--===========================================================================================  
--Which category contributes the most to overall sales

WITH sales_catgry AS 
(
	SELECT
		p.category,
		SUM(f.sales_amount) as total_sales
	FROM fact_sales f
	LEFT JOIN dim_products p
		on f.product_key = p.product_key
	GROUP BY category
)

SELECT 
	category,
	total_sales,
	SUM(total_sales) OVER () as overall_sales,
	CONCAT(ROUND((CAST(total_sales as FLOAT) / NULLIF(SUM(total_sales) OVER (),0))*100, 2),'%') as pct_of_total
FROM sales_catgry
ORDER BY total_sales DESC;

--===========================================================================================
--                    [Data Segmentation]
--===========================================================================================  
--Segment products into cost ranges and count how many products fall into each segment

WITH cost_segment AS
(
	SELECT 
		product_key,
		product_name,
		cost,
		CASE 
			WHEN cost < 100 THEN 'Below 100'
			 WHEN cost BETWEEN 100 AND 500 THEN '100-500'
			WHEN cost BETWEEN 500 AND 1000 THEN '500-1000'
		 ELSE 'Above 1000'
		END as cost_range
	FROM dim_products
)

SELECT 
	cost_range,
	COUNT(product_key) as product_count
FROM cost_segment
GROUP BY cost_range
ORDER BY product_count DESC;

--===========================================================================================
/* 
	Group customers into three segments based on their spending behavior:
	- VIP: Customers with atleast 12 months of history and spending more than $5000.
	- Regular:Customers with atleast 12 months of history but spending $5000 or less.
	- New: Customers with a lifespan less than 12 months.
*/

WITH customer_spending AS
(
	SELECT 
		c.customer_key,
		SUM(f.sales_amount) as total_spending,
		MIN(order_date) as first_order,
		MAX(order_date) as last_order,
		DATEDIFF(month, MIN(order_date), MAX(order_date)) as lifespan
	FROM fact_sales f
	LEFT JOIN dim_customers c
		ON c.customer_key = f.customer_key
	GROUP BY c.customer_key
)

SELECT
	customer_segment,
	COUNT(customer_key) as total_customers
	FROM(
		SELECT 
			customer_key,
			CASE 
				 WHEN lifespan >= 12 AND total_spending > 5000 THEN 'VIP'
				 WHEN lifespan >= 12 AND total_spending <= 5000 THEN 'REGULAR'
				ELSE 'NEW'
			END as customer_segment
		FROM customer_spending )t
GROUP BY customer_segment
ORDER BY total_customers DESC;

--=========================================================================================================================================

					/*====================================================================================
	              								   	CUSTOMER REPORT
				     ======================================================================================
Purpose:
		- This report consolidates key customer metrics and behaviors

Highlights:
	1. Gather essential fields such as names, ages and transaction details.
	2. Segment customers into categories (VIP, Regular, New) and age groups.
	3. Aggregates customer-level metrics:
		- total orders
		- total sales
		- total quantity purchased
		- total products
		- lifespan (in Months)
	4. Calculate valuable KPI's:
		- recency (months since last order)
		- average order value
		- average monthly spend
========================================================================================*/
IF OBJECT_ID ('report_customers','V') IS NOT NULL
DROP VIEW report_customers;
GO

CREATE VIEW report_customers AS
WITH base_query AS(
/*----------------------------------------------------------------------------------
1) Base Query: Retrieves core columns from tables
----------------------------------------------------------------------------------*/
	SELECT 
		f.order_number,
		f.product_key,
		f.order_date,
		f.sales_amount,
		f.quantity,
		c.customer_key,
		c.customer_number,
		CONCAT(c.first_name, ' ', c.last_name) as customer_name,
		c.country,
		DATEDIFF(year, c.birthdate, GETDATE()) as AGE
	FROM fact_sales f
	LEFT JOIN dim_customers c
		ON f.customer_key = c.customer_key
	WHERE order_date IS NOT NULL
)
, customer_aggregation AS (
/*----------------------------------------------------------------------------------
2) Customer Aggregations: Summarizes key metrics at the customer level 
----------------------------------------------------------------------------------*/
	Select 
		customer_key,
		customer_number,
		customer_name,
		age,
		COUNT(DISTINCT order_number) as total_orders,
		SUM(sales_amount) as total_sales,
		SUM(quantity) as total_quantity,
		COUNT(DISTINCT product_key) as total_products,
		MIN(order_date) as first_order,
		MAX(order_date) as last_order,
		DATEDIFF(month, MIN(order_date), MAX(order_date)) as life_span
	FROM base_query
	GROUP BY customer_key,
			 customer_number,
			 customer_name,
			 age
	)
/*----------------------------------------------------------------------------------
3) Final Query: Combine all Customer results into one output 
----------------------------------------------------------------------------------*/
Select 
	customer_key,
	customer_number,
	customer_name,
	age,
	total_orders,
	total_sales,
	total_quantity,
	total_products,
	first_order,
	last_order,
	life_span,
	CASE 
		 WHEN age < 20 THEN 'Below 20'
		 WHEN age BETWEEN 20 AND 29 THEN '20-29'
		 WHEN age BETWEEN 30 AND 39 THEN '30-39'
		 WHEN age BETWEEN 40 AND 49 THEN '40-49'
	 ELSE '50 and Above'
	END AS age_grp,
	CASE
		 WHEN life_span >= 12 AND total_sales > 50000  THEN 'VIP'
		 WHEN life_span >= 12 AND total_sales <= 50000  THEN 'Regular'
	 ELSE 'New'
	END AS customer_segment,
	DATEDIFF(month, last_order, GETDATE()) as recency,
	-- Compute average order value (AOV): [Average Order Value = Total Sales / Total no. of orders ]
	CAST(total_sales AS FLOAT) / NULLIF(total_orders,0) as avg_order_value,
	-- Compute average monthly spend (AMS): [Average Monthly Spend  = Total Sales / No. of Months ]
	CASE
		WHEN  life_span = 0 THEN total_sales
		ELSE CAST(total_sales as FLOAT) / life_span
	END as avg_monthly_spend
FROM customer_aggregation;
GO

SELECT *
FROM report_customers;
GO
/*==================================================================================================
									Product REPORT
====================================================================================================
Purpose:
		- This report consolidates key product metrics and behaviors

Highlights:
	1. Gather essential fields such as product name, category, subcategory and cost.
	2. Segment products by revenue to identify High-Performers, Mid-Range or Low-Performers .
	3. Aggregates products-level metrics:
		- total orders
		- total sales
		- total quantity sold
		- total customers (unique)
		- lifespan (in Months)
	4. Calculate valuable KPI's:
		- recency (months since last sale)
		- average order revenue
		- average monthly revenue
====================================================================================================*/
DROP VIEW IF EXISTS report_products;
GO

CREATE VIEW report_products AS 
WITH base_query AS
(
/*----------------------------------------------------------------------------------
1) Base Query: Retrieves core columns from tables
----------------------------------------------------------------------------------*/
	SELECT 
		f.order_number,
		f.product_key,
		f.order_date,
		f.sales_amount,
		f.quantity,
		f.customer_key,
		p.product_name,
		p.category,
		p.subcategory,
		p.cost
	FROM fact_sales f
	LEFT JOIN dim_products p
		On f.product_key = p.product_key
	WHERE order_date IS NOT NULL
)
, product_aggregation AS (
/*----------------------------------------------------------------------------------
2) Product Aggregations: Summarizes key metrics at the product level 
----------------------------------------------------------------------------------*/

SELECT 
	product_key,
	product_name,
	category,
	subcategory,
	cost,
	MIN(order_date) as first_order,
	Max(order_date) as last_order,
	DATEDIFF(month, MIN(order_date),Max(order_date)) as lifespan,
	COUNT(DISTINCT order_number) as total_orders,
	SUM(sales_amount) as total_sales,
	SUM(quantity) as total_quantity,
	COUNT(DISTINCT customer_key) as total_customers,
	Round(AVG(CAST(sales_amount as FLOAT) / NULLIF(quantity,0)),2) as avg_selling_price
FROM base_query
GROUP BY product_key,
		 product_name,
		 category,
		 subcategory,
		 cost
)
/*----------------------------------------------------------------------------------
3) Final Query: Combine all product results into one output 
-----------------------------------------------------------------------------------*/

SELECT 
	product_key,
	product_name,
	category,
	subcategory,
	cost,
	lifespan,
	total_orders,
	total_sales,
	first_order,
	DATEDIFF(month, last_order, GETDATE()) as recency,
	CASE 
		 WHEN total_sales > 50000 THEN 'High Performers'
		 WHEN total_sales >= 10000 THEN 'Mid Performers'
	 ELSE 'Low Performers'
	END as product_segment,
-- Average Order Revenue (AOR)
	CAST(total_sales as FLOAT) / NULLIF(total_orders,0) as avg_order_revenue,
-- Average Monthly Revenue (AMR)
	CASE
		WHEN lifespan = 0 THEN total_sales
        ELSE CAST(total_sales AS FLOAT) / lifespan
	END AS avg_monthly_revenue,
	total_quantity,
	total_customers,
	avg_selling_price
FROM product_aggregation;
GO

SELECT *
FROM report_products;

SELECT *
FROM report_customers;

/*==========================================================================================================
                                        [Ranking Products]
1) Top 5 Products by Sales in Each Year
	-For every year, rank products based on total sales and return the top 5 products.*/
--==========================================================================================================

WITH base_query AS
(
	SELECT 
		YEAR(f.order_date) as order_yr,
		SUM(f.sales_amount) as total_sales,
		p.product_name
	FROM fact_sales f
	LEFT JOIN dim_products p
		ON f.product_key = p.product_key
	where order_date is not null
	GROUP BY YEAR(f.order_date), p.product_name
)

SELECT * 
	FROM(
		SELECT 
			order_yr,
			total_sales,
			product_name,
			DENSE_RANK() OVER (PARTITION BY order_yr ORDER BY total_sales DESC) rnk
		FROM base_query)t 
		WHERE rnk <= 5
/*==========================================================================================================
2) Best Selling Products and Worst selling products in Each Year
	- Find the highest-selling product for each year.
	- Find the lowest-selling product for each year.
===========================================================================================================*/
--Highest-selling
WITH yr_sales  AS
(
	SELECT 
		YEAR(f.order_date) as order_yr,
		SUM(f.sales_amount) as total_sales,
		p.product_name
	FROM fact_sales f
	LEFT JOIN dim_products p
		ON f.product_key = p.product_key
	where order_date is not null
	GROUP BY YEAR(f.order_date), p.product_name
)

SELECT * 
FROM(
	SELECT 
		order_yr,
		total_sales,
		product_name,
		DENSE_RANK() OVER (PARTITION BY order_yr ORDER BY total_sales desc) rnk
	FROM yr_sales )t 
	WHERE rnk = 1;

--Lowest-selling
WITH yr_sales  AS
(
	SELECT 
		YEAR(f.order_date) as order_yr,
		SUM(f.sales_amount) as total_sales,
		p.product_name
	FROM fact_sales f
	LEFT JOIN dim_products p
		ON f.product_key = p.product_key
	where order_date is not null
	GROUP BY YEAR(f.order_date), p.product_name
)

SELECT * 
FROM(
	SELECT 
		order_yr,
		total_sales,
		product_name,
		DENSE_RANK() OVER (PARTITION BY order_yr ORDER BY total_sales) rnk
	FROM yr_sales )t 
	WHERE rnk = 1;
/*===========================================================================================================
4) Top 3 Customers by Revenue
	- Rank customers based on total spending and return the top 3 customers.
============================================================================================================*/

WITH customer_sales AS
(
	SELECT 
	CONCAT(c.first_name, ' ', c.last_name) as customer_name,
	SUM(f.sales_amount) total_spending
	FROM fact_sales f
	LEFT JOIN dim_customers c
	ON c.customer_key = f.customer_key
	GROUP BY CONCAT(c.first_name, ' ', c.last_name)
)

SELECT *
FROM(
	SELECT
		customer_name,
		total_spending,
		DENSE_RANK() OVER(ORDER BY total_spending DESC) as rnk
	FROM customer_sales)t
WHERE rnk <= 3

/*============================================================================================================
5) Top 3 Customers Within Each Country
	- For every country, rank customers based on total spending and return the top 3.
============================================================================================================*/

WITH customer_spending AS
(
	SELECT 
		CONCAT(c.first_name, ' ', c.last_name) as customer_name,
		c.country,
		SUM(f.sales_amount) as total_spending
	FROM fact_sales f
	LEFT JOIN dim_customers c
		ON f.customer_key = c.customer_key
	GROUP BY c.country, CONCAT(c.first_name, ' ', c.last_name)
)
SELECT *
FROM(
	SELECT 
		customer_name,
		country,
		total_spending,
		DENSE_RANK() OVER(PARTITION BY country ORDER BY total_spending DESC) as rnk
	FROM customer_spending)t
WHERE rnk <= 3

/*============================================================================================================
6. Top Product in Every Category
	- Within each category, identify the product generating the highest revenue.
=============================================================================================================*/
WITH product_details AS
(
	SELECT
		p.product_name,
		p.category,
		SUM(f.sales_amount) as total_sales
	FROM fact_sales f
	LEFT JOIN dim_products p
		ON f.product_key = p.product_key
	GROUP BY p.product_name,p.category
)
SELECT *
FROM(
	SELECT
		product_name,
		category,
		total_sales,
		DENSE_RANK() OVER(PARTITION BY category ORDER BY total_sales DESC) as revenue
	FROM product_details)t
WHERE revenue = 1
ORDER BY total_sales DESC

/*============================================================================================================
7)Find Products Tied for Highest Revenue
	- Return all products sharing the highest sales within their category.
=============================================================================================================*/
WITH product_details AS
(
	SELECT
		p.product_name,
		p.category,
		SUM(f.sales_amount) as total_sales
	FROM dim_products p
	LEFT JOIN  fact_sales f
		ON f.product_key = p.product_key
		WHERE category IS NOT NULL
	GROUP BY p.product_name,p.category
	)
	
SELECT *
FROM(
	SELECT
		product_name,
		category,
		DENSE_RANK() OVER(PARTITION BY category ORDER BY total_sales DESC) as cat_revenue
	FROM product_details
	)t
WHERE cat_revenue = 1

/*============================================================================================================
8) Most Recent Order per Customer
	 - Return only the latest order placed by every customer.
=============================================================================================================*/

SELECT *
FROM (
	SELECT
		f.order_date,
		c.customer_key,
		CONCAT(c.first_name, ' ', c.last_name) as customer_name,
		ROW_NUMBER() OVER(PARTITION BY c.customer_key ORDER BY order_date DESC) as rn
	FROM fact_sales f
	LEFT JOIN dim_customers c
		ON c.customer_key = f.customer_key
	)t
WHERE rn = 1

/*============================================================================================================
9) Most Recently Sold Product per Category
	- Find the most recent product sold within each category.
=============================================================================================================*/

SELECT *
FROM(
	SELECT
		p.category,
		p.product_name,
		f.order_date,
		ROW_NUMBER() OVER (PARTITION BY category ORDER BY order_date DESC) as rn
	FROM fact_sales f
	LEFT JOIN dim_products p
		on p.product_key = f.product_key
		WHERE order_date IS NOT NULL)t
WHERE rn = 1

/*============================================================================================================
10) Monthly Best Seller
	 - For every month, find the product with the highest sales.
=============================================================================================================*/

SELECT *
FROM(
	SELECT
		MONTH(f.order_date) as order_month,
		p.product_name,
		SUM(f.sales_amount) as total_sales,
		DENSE_RANK() OVER(PARTITION BY MONTH(f.order_date) ORDER BY SUM(f.sales_amount) DESC) as rn
	FROM fact_sales f
	LEFT JOIN dim_products p
		ON f.product_key = p.product_key
		WHERE MONTH(f.order_date) IS NOT NULL
	GROUP BY p.product_name, MONTH(f.order_date)	
	)t
WHERE rn = 1

/*============================================================================================================
11) Largest Revenue Contributing Product per Category
	- Identify the product contributing the largest share of revenue within each category.
=============================================================================================================*/

WITH product_sales AS
(
	SELECT
		p.product_name,
		p.category,
		SUM(f.sales_amount) as total_sales
	FROM fact_sales f
	LEFT JOIN dim_products p
		ON f.product_key = p.product_key
	GROUP BY p.product_name, p.category
),
product_contribution AS
(
    SELECT
        category,
        product_name,
        total_sales,
        CONCAT(ROUND(CAST(total_sales as FLOAT) / SUM(total_sales) OVER(PARTITION BY category) * 100, 2),'%') AS contribution_pct
    FROM product_sales
)
SELECT *
FROM(
	SELECT
		product_name,
		category,
		total_sales,
		contribution_pct,
		DENSE_RANK() OVER(PARTITION BY category ORDER BY contribution_pct desc) as rnk
	FROM product_contribution)t
WHERE rnk = 1
ORDER BY contribution_pct DESC;

/*============================================================================================================
12) Top Customer for Each Product
	 - For every product, identify the customer who spent the most.
=============================================================================================================*/

WITH product_customer_sales AS
(
	SELECT 
		p.product_name,
		p.category,
		c.customer_key,
		SUM(f.sales_amount) as total_sales
	FROM fact_sales f
	LEFT JOIN dim_customers c
		ON f.customer_key= c.customer_key
	LEFT JOIN dim_products p
		ON f.product_key= p.product_key
	GROUP BY p.product_name, p.category, c.customer_key
)

SELECT *
FROM(
	SELECT
	product_name,
	category,
	customer_key,
	total_sales,
	DENSE_RANK() OVER(PARTITION BY product_name ORDER BY total_sales DESC) as rnk
	FROM product_customer_sales
	)t
WHERE rnk = 1

/*============================================================================================================
13) Customer Retention Leaderboard
	 - Rank customers based on lifespan (months between first and last purchase).
=============================================================================================================*/
WITH customer_lifespan AS
(
	SELECT
		CONCAT(c.first_name, ' ', c.last_name) as customer_name,
		DATEDIFF(month, MIN(f.order_date), MAX(f.order_date)) as lifespan
	FROM fact_sales f
	LEFT JOIN dim_customers c
		ON c.customer_key = f.customer_key
		GROUP BY CONCAT(c.first_name, ' ', c.last_name)
)
SELECT *
FROM(
	SELECT
	customer_name,
	lifespan,
	DENSE_RANK() OVER(ORDER BY LIFESPAN DESC) as rnk
	FROM customer_lifespan
	)t

/*============================================================================================================	
14) Highest Growth Product
Find the product with the highest year-over-year revenue growth.
=============================================================================================================*/

WITH product_sales AS
(
	SELECT
		YEAR(f.order_date) as order_yr,
		p.product_name,
		SUM(f.sales_amount) as total_sales
	FROM fact_sales f
	LEFT JOIN dim_products p
		ON f.product_key = p.product_key
	GROUP BY YEAR(f.order_date), p.product_name
),
yoy AS
  (
	SELECT
		order_yr,
		product_name,
		total_sales,
		LAG(total_sales)OVER(PARTITION BY product_name ORDER BY order_yr) as previous_yr_sales
	FROM product_sales
  ),
  growth AS(
	SELECT
		order_yr,
		product_name,
		total_sales,
		previous_yr_sales,
		total_sales - previous_yr_sales as revenue_grth
	FROM yoy
	WHERE previous_yr_sales IS NOT NULL
 )

	SELECT *
	FROM(
		SELECT *,
			DENSE_RANK() OVER(ORDER BY revenue_grth DESC) AS rnk
		FROM growth)t
	WHERE rnk = 1;

/*============================================================================================================	
15) Customer Spending Quartiles
	 - Divide customers into 4 groups based on total spending.
=============================================================================================================*/
WITH customer_spending AS
(
	SELECT
		c.customer_key,
		CONCAT(c.first_name,' ', c.last_name) as customer_name,
		SUM(f.sales_amount) as total_spending
		FROM fact_sales f
	LEFT JOIN dim_customers c
		ON f.customer_key = c.customer_key
	GROUP BY CONCAT(c.first_name,' ', c.last_name), c.customer_key
)

SELECT *,
NTILE(4) OVER(ORDER BY total_spending DESC) as cust_segment
FROM customer_spending;

/*============================================================================================================
16) Product Revenue Quartiles
	 - Segment products into Top 25%, Middle 50%, Bottom 25% based on revenue.
=============================================================================================================*/

WITH product_revenue AS
(
	SELECT
		p.product_name,
		p.product_key,
		SUM(f.sales_amount) as total_revenue
	FROM fact_sales f
	LEFT JOIN dim_products p
		ON f.product_key = p.product_key
	GROUP BY p.product_name, p.product_key
),
 quartile AS 
	(
		SELECT *,
			NTILE(4) OVER(ORDER BY total_revenue DESC) as revenue_quartile
		FROM product_revenue
	)

SELECT *,
CASE WHEN revenue_quartile = 1 THEN 'Top 25%'
	 WHEN revenue_quartile IN (2,3) THEN 'Middle 50%'
	 ELSE 'Bottom 25%'
END AS revenue_segment
FROM quartile
ORDER BY total_revenue DESC;

/*============================================================================================================
17) Customer Lifetime Value Ranking
	 - Rank customers by:
		- Customer Lifetime Value = Total Revenue Generated
Return Top 10 customers.
=============================================================================================================*/

WITH customer_spending AS
(
	SELECT
		c.customer_key,
		CONCAT(c.first_name,' ', c.last_name) as customer_name,
		SUM(f.sales_amount) as total_spending
		FROM fact_sales f
	LEFT JOIN dim_customers c
		ON f.customer_key = c.customer_key
	GROUP BY CONCAT(c.first_name,' ', c.last_name), c.customer_key
)

SELECT *
FROM(
	SELECT *,
	DENSE_RANK() OVER(ORDER BY total_spending DESC) as rnk
	FROM customer_spending
	)t
WHERE rnk<= 10;
Go

/*============================================================================================================
Find all orders placed in the last 30 days. Also, extract the month and year from the order date.
=============================================================================================================*/
SELECT
    order_number,
    customer_key,
    order_date,
    MONTH(order_date) AS order_month,
    YEAR(order_date) AS order_year
FROM fact_sales
WHERE order_date >= DATEADD(DAY, -30, GETDATE());

/*==============================================================================================================================
--Calculate the month-over-month revenue growth. Show current month revenue, previous month revenue, and percentage change.
===============================================================================================================================*/

SELECT *,
       current_sales - prev_sales AS revenue_diff,
       ROUND(
            (current_sales - prev_sales) * 100.0
            / NULLIF(prev_sales,0),
            2
       ) AS percentage_change
FROM
(
    SELECT
        DATETRUNC(month, order_date) AS order_month,
        SUM(sales_amount) AS current_sales,
        LAG(SUM(sales_amount))
            OVER(ORDER BY DATETRUNC(month, order_date)) AS prev_sales
    FROM fact_sales
    WHERE order_date IS NOT NULL
    GROUP BY DATETRUNC(month, order_date)
) t;

/*===========================================================================================
-- Find the running total of sales by date.
============================================================================================*/

SELECT *,
       SUM(total_sales) OVER(ORDER BY order_date) AS running_total
FROM
(
    SELECT
        order_date,
        SUM(sales_amount) AS total_sales
    FROM fact_sales
    WHERE order_date IS NOT NULL
    GROUP BY order_date
) t;

/*===========================================================================================
