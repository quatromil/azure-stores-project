-- Top 15 best-selling products
SELECT
    s.product_id,
    p.product_name,
    SUM(s.quantity) AS total_quantity
FROM sales s
LEFT JOIN products p
    ON s.product_id = p.product_id
GROUP BY s.product_id, p.product_name
ORDER BY total_quantity DESC
LIMIT 15;