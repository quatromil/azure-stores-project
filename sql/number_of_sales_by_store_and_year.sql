-- Number of sales by store and year
SELECT
    store,
    YEAR(sale_date) AS year,
    COUNT(sale_id) AS sales_count
FROM sales
GROUP BY store, YEAR(sale_date)
ORDER BY store, YEAR(sale_date);
