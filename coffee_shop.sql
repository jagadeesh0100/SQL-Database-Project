/*
   coffee_shop.sql
   Builds a synthetic database for a fictional UK coffee-shop chain
   using ONLY SQLite SQL.

   Tables:  stores (1)--(N) orders (N)--(1) customers
            orders (1)--(N) order_items (N)--(1) products
   order_items has a COMPOUND primary key (order_id, product_id) made of
   two FOREIGN keys.
*/
PRAGMA foreign_keys = ON;

DROP TABLE IF EXISTS order_items;
DROP TABLE IF EXISTS orders;
DROP TABLE IF EXISTS products;
DROP TABLE IF EXISTS customers;
DROP TABLE IF EXISTS stores;
/*
   STEP 1: CREATE TABLES (schema + constraints)
   CHECK constraints stop bad data (negative prices, satisfaction outside 1-5,
   sizes not in the allowed list).
*/
CREATE TABLE stores (
    store_id         INTEGER PRIMARY KEY,
    city             TEXT    NOT NULL,                              -- NOMINAL
    store_size       TEXT    NOT NULL
                     CHECK (store_size IN ('Kiosk','Small','Medium','Large')), -- ORDINAL
    opening_year     INTEGER NOT NULL CHECK (opening_year BETWEEN 2005 AND 2025), -- INTERVAL
    seating_capacity INTEGER NOT NULL CHECK (seating_capacity >= 0)  -- RATIO
);

CREATE TABLE customers (
    customer_id   INTEGER PRIMARY KEY,      -- pseudonymous ID: no names/emails stored
    age           INTEGER CHECK (age BETWEEN 16 AND 90),                -- RATIO
    loyalty_tier  TEXT NOT NULL
                  CHECK (loyalty_tier IN ('None','Bronze','Silver','Gold')), -- ORDINAL
    loyalty_rank  INTEGER NOT NULL CHECK (loyalty_rank BETWEEN 0 AND 3), -- numeric order of the tier
    signup_date   TEXT NOT NULL,                                        -- INTERVAL (date)
    home_store_id INTEGER NOT NULL REFERENCES stores(store_id)          -- FOREIGN KEY
);

CREATE TABLE products (
    product_id   INTEGER PRIMARY KEY,
    product_name TEXT NOT NULL,
    category     TEXT NOT NULL,                                         -- NOMINAL
    size         TEXT NOT NULL CHECK (size IN ('Small','Medium','Large','N/A')), -- ORDINAL
    base_price   REAL NOT NULL CHECK (base_price > 0),                  -- RATIO (GBP)
    is_hot       INTEGER NOT NULL CHECK (is_hot IN (0,1)),
    UNIQUE (product_name, size)
);

CREATE TABLE orders (
    order_id       INTEGER PRIMARY KEY,
    customer_id    INTEGER REFERENCES customers(customer_id),  -- FK; NULL = anonymous walk-in
    store_id       INTEGER NOT NULL REFERENCES stores(store_id), -- FK
    order_datetime TEXT NOT NULL,                                -- INTERVAL
    outside_temp_c REAL NOT NULL,                                -- INTERVAL (0 °C is not "no heat")
    payment_method TEXT NOT NULL
                   CHECK (payment_method IN ('Card','Contactless','Mobile App','Cash')), -- NOMINAL
    satisfaction   INTEGER CHECK (satisfaction BETWEEN 1 AND 5), -- ORDINAL (1-5 survey); NULL = not answered
    order_total    REAL NOT NULL CHECK (order_total >= 0)        -- RATIO
);

CREATE TABLE order_items (
    order_id   INTEGER NOT NULL REFERENCES orders(order_id),     -- FK
    product_id INTEGER NOT NULL REFERENCES products(product_id), -- FK
    quantity   INTEGER NOT NULL CHECK (quantity > 0),            -- RATIO
    unit_price REAL    NOT NULL CHECK (unit_price > 0),          -- RATIO
    line_total REAL    NOT NULL CHECK (line_total > 0),          -- RATIO
    PRIMARY KEY (order_id, product_id)                           -- COMPOUND KEY
);
/*
   STEP 2: SMALL LOOKUP TABLES (typed by hand, they are the "real world")
*/
INSERT INTO stores VALUES
 (1,'London','Large',2008,72),     (2,'London','Medium',2012,40),
 (3,'London','Kiosk',2019,0),      (4,'Manchester','Medium',2010,35),
 (5,'Manchester','Small',2016,18), (6,'Manchester','Large',2014,60),
 (7,'Birmingham','Medium',2011,30),(8,'Birmingham','Small',2018,20),
 (9,'Leeds','Medium',2013,28),     (10,'Leeds','Kiosk',2021,0),
 (11,'Bristol','Small',2015,22),   (12,'Hatfield','Small',2017,15),
 (13,'Edinburgh','Medium',2009,45),(14,'Edinburgh','Kiosk',2020,0),
 (15,'Cardiff','Small',2022,16);

-- Every drink comes in 3 cup sizes; bigger sizes cost more (x1.2, x1.4).
WITH menu(name, cat, price, hot) AS (VALUES
   ('Espresso','Hot Coffee',2.10,1), ('Americano','Hot Coffee',2.60,1),
   ('Latte','Hot Coffee',3.20,1),    ('Cappuccino','Hot Coffee',3.20,1),
   ('Flat White','Hot Coffee',3.30,1),('Mocha','Hot Coffee',3.50,1),
   ('Iced Latte','Cold Coffee',3.40,0),('Cold Brew','Cold Coffee',3.30,0),
   ('Frappe','Cold Coffee',3.90,0),  ('English Breakfast Tea','Tea',2.20,1),
   ('Chai Latte','Tea',3.10,1),      ('Iced Tea','Tea',2.70,0),
   ('Hot Chocolate','Other Drinks',3.00,1),('Fruit Smoothie','Other Drinks',3.80,0)),
 sizes(size, mult, ord) AS (VALUES ('Small',1.0,1),('Medium',1.2,2),('Large',1.4,3))
INSERT INTO products (product_name, category, size, base_price, is_hot)
SELECT name, cat, size, ROUND(price * mult, 2), hot
FROM menu CROSS JOIN sizes
ORDER BY name, ord;

INSERT INTO products (product_name, category, size, base_price, is_hot) VALUES
 ('Croissant','Bakery','N/A',2.30,0), ('Blueberry Muffin','Bakery','N/A',2.50,0),
 ('Cinnamon Roll','Bakery','N/A',2.80,0), ('Ham & Cheese Toastie','Savoury','N/A',4.50,1),
 ('Vegan Wrap','Savoury','N/A',4.80,0), ('Porridge Pot','Savoury','N/A',3.20,1);
/*
   STEP 3: CUSTOMERS (1,500 random rows)
   Important SQLite detail: random() gives a new value EVERY time it is
   written, so each random number is first saved in a TEMP table and then
   reused. Otherwise loyalty_tier and loyalty_rank could disagree.
*/
CREATE TEMP TABLE cust_gen AS
WITH RECURSIVE seq(n) AS (SELECT 1 UNION ALL SELECT n + 1 FROM seq WHERE n < 1500)
SELECT n AS customer_id,
       -- sum of 3 random numbers -> bell-shaped ages, mostly 25-45
       16 + ABS(RANDOM()) % 14 + ABS(RANDOM()) % 14 + ABS(RANDOM()) % 14 AS age,
       ABS(RANDOM()) % 100  AS r_tier,
       ABS(RANDOM()) % 1095 AS days_before,   -- signed up in the 3 years before 2025
       ABS(RANDOM()) % 100  AS r_store
FROM seq;

INSERT INTO customers
SELECT customer_id,
       age,
       -- skewed: most customers are casual, few are Gold
       CASE WHEN r_tier < 40 THEN 'None' WHEN r_tier < 70 THEN 'Bronze'
            WHEN r_tier < 90 THEN 'Silver' ELSE 'Gold' END,
       CASE WHEN r_tier < 40 THEN 0 WHEN r_tier < 70 THEN 1
            WHEN r_tier < 90 THEN 2 ELSE 3 END,
       DATE('2025-01-01', '-' || days_before || ' days'),
       -- busier cities (London) get more customers
       CASE WHEN r_store < 20 THEN 1 WHEN r_store < 30 THEN 2 WHEN r_store < 35 THEN 3
            WHEN r_store < 45 THEN 4 WHEN r_store < 50 THEN 5 WHEN r_store < 58 THEN 6
            WHEN r_store < 66 THEN 7 WHEN r_store < 70 THEN 8 WHEN r_store < 76 THEN 9
            WHEN r_store < 78 THEN 10 WHEN r_store < 85 THEN 11 WHEN r_store < 88 THEN 12
            WHEN r_store < 94 THEN 13 WHEN r_store < 96 THEN 14 ELSE 15 END
FROM cust_gen;
/*
   STEP 4: ORDERS (5,000 random rows during 2025)
*/
CREATE TEMP TABLE order_gen AS
WITH RECURSIVE seq(n) AS (SELECT 1 UNION ALL SELECT n + 1 FROM seq WHERE n < 5000)
SELECT n AS order_id,
       ABS(RANDOM()) % 365  AS day_off,
       ABS(RANDOM()) % 65   AS r_hour,
       ABS(RANDOM()) % 3600 AS secs,
       ABS(RANDOM()) % 71   AS r_temp,
       ABS(RANDOM()) % 100  AS r_walkin,
       1 + ABS(RANDOM()) % 1500 AS cust,
       ABS(RANDOM()) % 100  AS r_home,
       1 + ABS(RANDOM()) % 15 AS rand_store,
       ABS(RANDOM()) % 100  AS r_pay,
       ABS(RANDOM()) % 100  AS r_answer,
       ABS(RANDOM()) % 100  AS r_sat,
       ABS(RANDOM()) % 100  AS r_items,
       ABS(RANDOM()) % 100  AS r_food
FROM seq;

-- Turn the random numbers into realistic values (no new random() calls here).
CREATE TEMP TABLE order_calc AS
SELECT g.*,
       CASE WHEN r_walkin < 30 THEN NULL ELSE cust END AS customer_id,   -- 30% walk-ins
       DATETIME(DATE('2025-01-01', '+' || day_off || ' days'),
                '+' || CASE WHEN r_hour < 9  THEN 7  WHEN r_hour < 19 THEN 8   -- morning rush
                            WHEN r_hour < 27 THEN 9  WHEN r_hour < 32 THEN 10
                            WHEN r_hour < 36 THEN 11 WHEN r_hour < 43 THEN 12   -- lunch
                            WHEN r_hour < 49 THEN 13 WHEN r_hour < 53 THEN 14
                            WHEN r_hour < 57 THEN 15 WHEN r_hour < 60 THEN 16
                            WHEN r_hour < 62 THEN 17 WHEN r_hour < 64 THEN 18
                            ELSE 19 END || ' hours',
                '+' || secs || ' seconds') AS order_datetime,
       -- UK monthly average temperature +/- 3.5 °C of random noise
       ROUND(CASE CAST(STRFTIME('%m', DATE('2025-01-01', '+' || day_off || ' days')) AS INTEGER)
               WHEN 1 THEN 4 WHEN 2 THEN 5 WHEN 3 THEN 7 WHEN 4 THEN 9
               WHEN 5 THEN 12 WHEN 6 THEN 15 WHEN 7 THEN 17 WHEN 8 THEN 17
               WHEN 9 THEN 14 WHEN 10 THEN 11 WHEN 11 THEN 7 ELSE 5 END
             + (r_temp - 35) / 10.0, 1) AS temp_c
FROM order_gen g;

INSERT INTO orders
SELECT o.order_id,
       o.customer_id,
       -- members visit their home store 75% of the time
       CASE WHEN o.customer_id IS NOT NULL AND o.r_home < 75
            THEN c.home_store_id ELSE o.rand_store END,
       o.order_datetime,
       o.temp_c,
       -- higher loyalty tiers use the app more and cash less
       CASE WHEN o.r_pay < 35 THEN 'Card'
            WHEN o.r_pay < 70 THEN 'Contactless'
            WHEN o.r_pay < 80 + COALESCE(c.loyalty_rank, 0) * 5 THEN 'Mobile App'
            ELSE 'Cash' END,
       -- 40% skip the survey; answers lean positive
       CASE WHEN o.r_answer < 40 THEN NULL
            WHEN o.r_sat < 3  THEN 1 WHEN o.r_sat < 10 THEN 2
            WHEN o.r_sat < 30 THEN 3 WHEN o.r_sat < 70 THEN 4 ELSE 5 END,
       0     -- order_total is filled in at Step 6
FROM order_calc o
LEFT JOIN customers c ON c.customer_id = o.customer_id;
/*
   STEP 5: ORDER ITEMS (1-3 drinks per order + food 35% of the time)
   Warmer days -> higher chance of a cold drink.
*/
CREATE TEMP TABLE order_plan AS
SELECT o.order_id, o.outside_temp_c AS t,
       CASE WHEN g.r_items < 70 - COALESCE(c.loyalty_rank,0) * 5 THEN 1
            WHEN g.r_items < 92 - COALESCE(c.loyalty_rank,0) * 2 THEN 2
            ELSE 3 END AS n_drinks,
       g.r_food < 35 AS has_food
FROM orders o
JOIN order_gen g ON g.order_id = o.order_id
LEFT JOIN customers c ON c.customer_id = o.customer_id;

-- Numbered lists so a random number can pick a product.
CREATE TEMP TABLE hot_drinks  AS SELECT ROW_NUMBER() OVER (ORDER BY product_id) AS rn, product_id
                                 FROM products WHERE size <> 'N/A' AND is_hot = 1;
CREATE TEMP TABLE cold_drinks AS SELECT ROW_NUMBER() OVER (ORDER BY product_id) AS rn, product_id
                                 FROM products WHERE size <> 'N/A' AND is_hot = 0;
CREATE TEMP TABLE food_items  AS SELECT ROW_NUMBER() OVER (ORDER BY product_id) AS rn, product_id
                                 FROM products WHERE size = 'N/A';

-- One row per drink slot, with its random numbers saved.
CREATE TEMP TABLE drink_slots AS
WITH slots(s) AS (VALUES (1),(2),(3))
SELECT p.order_id, p.t, ABS(RANDOM()) % 100 AS r_cold, ABS(RANDOM()) % 1000 AS r_pick
FROM order_plan p JOIN slots ON slots.s <= p.n_drinks;

CREATE TEMP TABLE all_lines AS
SELECT d.order_id,
       CASE WHEN d.r_cold < (CASE WHEN d.t < 8 THEN 5 WHEN d.t < 12 THEN 15
                                  WHEN d.t < 16 THEN 30 WHEN d.t < 20 THEN 55 ELSE 75 END)
            THEN (SELECT product_id FROM cold_drinks
                  WHERE rn = 1 + d.r_pick % (SELECT COUNT(*) FROM cold_drinks))
            ELSE (SELECT product_id FROM hot_drinks
                  WHERE rn = 1 + d.r_pick % (SELECT COUNT(*) FROM hot_drinks))
       END AS product_id
FROM drink_slots d;

CREATE TEMP TABLE food_slots AS
SELECT order_id, ABS(RANDOM()) % 1000 AS r_pick FROM order_plan WHERE has_food;

INSERT INTO all_lines
SELECT f.order_id,
       (SELECT product_id FROM food_items WHERE rn = 1 + f.r_pick % (SELECT COUNT(*) FROM food_items))
FROM food_slots f;

-- If the same product is picked twice in one order, it becomes quantity 2
-- (this is what keeps the compound key (order_id, product_id) unique).
INSERT INTO order_items
SELECT l.order_id, l.product_id, COUNT(*), p.base_price, ROUND(p.base_price * COUNT(*), 2)
FROM all_lines l JOIN products p ON p.product_id = l.product_id
GROUP BY l.order_id, l.product_id;
/*
   STEP 6: ORDER TOTALS = sum of the order's line totals
*/
UPDATE orders
SET order_total = (SELECT ROUND(SUM(line_total), 2)
                   FROM order_items i WHERE i.order_id = orders.order_id);

DROP TABLE cust_gen;  DROP TABLE order_gen;  DROP TABLE order_calc;
DROP TABLE order_plan; DROP TABLE hot_drinks; DROP TABLE cold_drinks;
DROP TABLE food_items; DROP TABLE drink_slots; DROP TABLE food_slots;
DROP TABLE all_lines;
/*
   STEP 7: CHECKS (run these and screenshot the results for the report)
*/
SELECT 'stores', COUNT(*) FROM stores
UNION ALL SELECT 'customers', COUNT(*) FROM customers
UNION ALL SELECT 'products', COUNT(*) FROM products
UNION ALL SELECT 'orders', COUNT(*) FROM orders
UNION ALL SELECT 'order_items', COUNT(*) FROM order_items;

-- Realism check: cold drinks should be bought on warmer days.
-- SELECT p.category, ROUND(AVG(o.outside_temp_c),1) AS avg_temp, COUNT(*) AS items
-- FROM order_items i JOIN orders o USING(order_id) JOIN products p USING(product_id)
-- GROUP BY p.category;
