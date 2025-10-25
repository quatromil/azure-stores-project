-- Total sales by store and year
SELECT
    store,
    YEAR(sale_date) AS year,
    SUM(total_amount) AS total_sales
FROM sales
GROUP BY store, YEAR(sale_date)
ORDER BY store, YEAR(sale_date);