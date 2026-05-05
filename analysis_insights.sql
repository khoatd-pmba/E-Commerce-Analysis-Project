-- Check the rows of the Database as well as the first 5 rows --
SELECT count(*) from dbo.sales_large
SELECT top  5 *from dbo.sales_large

-- Create a new customer table--
SELECT
    customer_ID,
    customer_name,
    age,
    gender,
    age_group,
    cast(MAX(CAST(churn AS INT)) AS BIT) AS churn,
    COUNT(*) AS total_transactions,
    ROUND(SUM(total_purchase_amount * 1.0), 2) AS total_spent,
    ROUND(AVG(total_purchase_amount * 1.0), 2) AS avg_order_value,
    ROUND(SUM(CASE WHEN [returns] = 1 THEN 1.0 ELSE 0 END) / COUNT(*) * 100, 2) AS avg_return_rate
INTO dbo.customer_base
FROM dbo.sales_large
GROUP BY customer_ID, customer_name, age, gender, age_group

--Verify--
select top 5 * from dbo.customer_base

-- Calculate Sales KPIs --
select sum(total_purchase_amount) as total_revenue,
        count(*) as total_transactions,
        count(distinct(customer_ID)) as total_customers,
        cast(round(sum(total_purchase_amount) * 1.0 / count(*),2) as decimal (10,2)) as average_order_value
from dbo.sales_large

-- Category Performance--
select product_category, sum(total_purchase_amount) as total_revenue,
        count(*) as total_transactions,
        round(avg(total_purchase_amount * 1.0), 2)  as average_order_value,
        cast(ROUND(sum(total_purchase_amount * 1.0) * 100.0 /
                sum(sum(total_purchase_amount * 1.0)) OVER(), 2) as decimal(10,2)) as revenue_pct,
        cast(round(sum(case when [returns] = 1 then 1.0 else 0 end) / count(*) * 100,2) as decimal (10,2)) as return_rate_pct
from dbo.sales_large
GROUP BY product_category

--Payment Method Performance--
select payment_method, sum(total_purchase_amount) as total_revenue,
        count(*) as total_transactions,
        round(avg(total_purchase_amount * 1.0), 2)  as average_order_value,
        cast(ROUND(sum(total_purchase_amount * 1.0) * 100.0 /
                sum(sum(total_purchase_amount * 1.0)) OVER(), 2) as decimal(10,2)) as revenue_pct,
        cast(round(sum(case when [returns] = 1 then 1.0 else 0 end) / count(*) * 100,2) as decimal (10,2)) as return_rate_pct
from dbo.sales_large
GROUP BY payment_method

-- Total Customers and Overview--
select count(distinct(customer_ID)) as total_customers,
        round(avg(age),2) as avg_age,
        sum(case when churn = 1 then 1 else 0 end) as churrned_customers,
        cast(round( sum(case when churn = 1 then 1.0 else 0 end)/ count(distinct(customer_ID)) *100,2) as decimal(10,2)) as churn_rate_pct
from (select distinct customer_ID, age, churn
        from dbo.sales_large
) as customer_base


-- Customer age segmentation--
alter table dbo.sales_large
add age_group NVARCHAR (20)

update dbo.sales_large
set age_group = case 
        when age >= 65 then '65 and above'
        when age BETWEEN 55 and 64 then '55-64'
        when age BETWEEN 45 and 54 then '45-54'
        when age BETWEEN 35 and 44 then '35-44'
        when age BETWEEN 25 and 34 then '25-34'
        when age between 18 and 24 then '18-24'
        else 'Unknown'
end 

select age_group, count(distinct(customer_ID)) as total_customers, count(*) as total_transactions
from dbo.sales_large
GROUP BY age_group
ORDER BY age_group asc

-- Age Group: Churn Rates--
select age_group, 
        count(customer_ID) as total_customers, 
        sum(cast(churn as int)) as total_churned,
        cast(round(sum(cast (churn as int)) * 100.0 / count(customer_ID),2) as decimal (10,2)) as churn_rate_pct
from dbo.customer_base
group by age_group

-- Age Group: Transactional Metrics--
select age_group,
        count(*) total_transactions,
        count(distinct(customer_ID)) as total_customers,
        round(sum(total_purchase_amount) *1.0,2) as total_revenue,
        round(avg(total_purchase_amount) * 1.0, 2) as average_order_value,
        cast(round(sum(case when [returns] = 1 then 1.0 else 0 end) / count(*) * 100,2) as decimal (10,2)) as return_rate_pct,
        cast(round(sum(total_purchase_amount *1.0) *100.0 / sum(sum(total_purchase_amount * 1.0)) over(), 2) as decimal (10,2)) as revenue_pct
from dbo.sales_large
group by age_group
order by age_group asc

-- Gender: Churn Rates--
select gender, 
        count(customer_ID) as total_customers, 
        sum(cast(churn as int)) as total_churned,
        cast(round(sum(cast (churn as int)) * 100.0 / count(customer_ID),2) as decimal (10,2)) as churn_rate_pct
from dbo.customer_base
group by gender

-- Gender: Transactional Metrics--
select gender,
        count(*) total_transactions,
        count(distinct(customer_ID)) as total_customers,
        round(sum(total_purchase_amount) *1.0,2) as total_revenue,
        round(avg(total_purchase_amount) * 1.0, 2) as average_order_value,
        cast(round(sum(case when [returns] = 1 then 1.0 else 0 end) / count(*) * 100,2) as decimal (10,2)) as return_rate_pct,
        cast(round(sum(total_purchase_amount *1.0) *100.0 / sum(sum(total_purchase_amount * 1.0)) over(), 2) as decimal (10,2)) as revenue_pct
from dbo.sales_large
group by gender
order by gender


--RFM Analysis--
-- Step 1: Calculate base metrics--
with rfm_base as(
        select customer_ID,
        max(purhcase_date) as last_purchase_date,
        count(*) as frequency,
        round(sum(total_purchase_amount * 1.0),2) as monetary,
        datediff(day, max(purhcase_date), '2023-10-01') as recency_days
from dbo.sales_large
group by customer_ID
),

--Step 2: Score on a Scale 1-5--
rfm_scored as (
        select customer_ID,
        recency_days,
        frequency,
        monetary,
        ntile(5) over (order by recency_days desc) as r_score,
        NTILE(5) over (order by frequency asc) as f_score,
        ntile(5) over (order by monetary asc) as m_score
        from rfm_base
),

--Step 3: Combining those scores--
rfm_total_scored as (
        select customer_ID,
        recency_days,
        frequency,
        monetary,
        r_score,
        f_score,
        m_score,
        r_score + f_score + m_score as total_score
from rfm_scored
)

-- Step 4: Segmentation--
select customer_ID,
        recency_days,
        frequency,
        monetary,
        r_score,
        f_score,
        m_score,
        total_score,
        case 
                when total_score >= 13 then 'Champion Customer'
                when total_score >= 10 then 'Loyal Customer'
                when total_score >=7 then 'Potential Loyalists'
                when total_score >=4 then 'At-Risk'
                else 'Lost Customer'
        end as 'customer_segment'
into dbo.rfm_segments
from rfm_total_scored
ORDER BY total_score DESC



--Verify--
select count(*) from dbo.rfm_segments
select top 5 *from dbo.rfm_segments

-- Verify the validity--
select customer_segment,
        avg(recency_days) as avg_recency,
        avg(frequency) as avg_frequency,
        avg(monetary) as avg_monetary
from dbo.rfm_segments
group by customer_segment

-- Step 5: Total Numbers for each segment--
SELECT customer_segment,
        count(customer_ID) as number_of_customers,
        cast(round(count(customer_ID) * 100.0 /sum(count(customer_ID)) over (), 2)as decimal (10,2)) as segment_pct
from dbo.rfm_segments
GROUP BY customer_segment

-- Orders--
alter table dbo.rfm_segments
add segment_order int;

update dbo.rfm_segments
set segment_order = case
    when customer_segment = 'Champion Customer' then 1
    when customer_segment = 'Loyal Customer'    then 2
    when customer_segment = 'Potential Loyalist'then 3
    when customer_segment = 'At-Risk'then 4
    when customer_segment = 'Lost Customer'then 5
end;

select top 5 * from dbo.rfm_segments
select count(*) from dbo.rfm_segments