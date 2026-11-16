--	TABLE CRM.CUST_INFO
-- Check for Nulls or Duplicates in Primary Key
-- Expectation: No result
SELECT [cst_id], COUNT(*)
FROM [DataWarehouse].[bronze].[crm_cust_info]
GROUP BY cst_id
HAVING COUNT(*) > 1 OR cst_id IS NULL;

-- Check for unwanted spaces
-- Expectation: No result
SELECT cst_key
FROM [DataWarehouse].[bronze].[crm_cust_info]
WHERE cst_key != TRIM(cst_key)

SELECT cst_firstname
FROM [DataWarehouse].[bronze].[crm_cust_info]
WHERE cst_firstname != TRIM(cst_firstname)

SELECT cst_lastname
FROM [DataWarehouse].[bronze].[crm_cust_info]
WHERE cst_lastname != TRIM(cst_lastname)

SELECT cst_gndr
FROM [DataWarehouse].[bronze].[crm_cust_info]
WHERE cst_gndr != TRIM(cst_gndr)

-- Check for consistency in values of cardinality columns
SELECT DISTINCT cst_gndr
FROM [DataWarehouse].[bronze].[crm_cust_info]
 
-- After adding the cleaned data into the silver layer table
-- use the above quality checks on its tables to verify whether 
-- the cleaning was successful

--	TABLE CRM.PRD_INFO
-- Check for Nulls or Duplicates in Primary Key
-- Expectation: No result
SELECT [prd_id], COUNT(*)
FROM [DataWarehouse].[bronze].[crm_prd_info]
GROUP BY prd_id
HAVING COUNT(*) > 1 OR prd_id IS NULL;

-- Extracting the cat_id from prd_key to make it easier to join with table erp.px_cat_g1v2
-- Subsituting '-' in cat_id with '_' to ensure consistency with table erp.px_cat_g1v2
-- Extracting the sls_prd_key from prd_key to make it easier to join with table crm.sales_details
SELECT
	prd_id,
	prd_key,
	REPLACE(SUBSTRING(prd_key, 1, 5), '-', '_')  AS cat_id,
	SUBSTRING(prd_key, 7, LEN(prd_key)) AS prd_key,
	prd_nm,
	prd_cost,
	prd_line,
	prd_start_dt,	
	prd_end_dt 
FROM [DataWarehouse].[bronze].[crm_prd_info]

-- Checked for co-existence
SELECT sls_prd_key
FROM [DataWarehouse].[bronze].[crm_sales_details]

SELECT DISTINCT id
FROM [DataWarehouse].[bronze].[erp_px_cat_g1v2]

-- Check for unwanted spaces
-- Expectation: No result
SELECT prd_nm
FROM [DataWarehouse].[bronze].[crm_prd_info]
WHERE prd_nm != TRIM(prd_nm)

-- Check for NULLs or Negative Numbers 
-- Expectation: No result
SELECT prd_cost
FROM [DataWarehouse].[bronze].[crm_prd_info]
WHERE prd_cost < 0 OR prd_cost IS NULL

-- Data Standardization and Consistency
SELECT DISTINCT prd_line 
FROM [DataWarehouse].[bronze].[crm_prd_info]

-- Check for Invalid Date Orders
-- Expectation: start_date should not come after end_date, start_date should not be NULL
-- Same product should not have different prices within the same time span 
SELECT *
FROM [DataWarehouse].[bronze].[crm_prd_info]
WHERE prd_end_dt < prd_start_dt

--	TABLE CRM.SALES_DETAILS

-- Check if all ids from crm_sales_details are present in crm_cust_info as well
SELECT *
FROM [DataWarehouse].[bronze].[crm_sales_details]
WHERE sls_cust_id NOT IN (SELECT cst_id FROM silver.crm_cust_info)

-- Check for Invalid Dates
SELECT NULLIF(sls_order_dt, 0) AS sls_order_dt
FROM [DataWarehouse].[bronze].[crm_sales_details]
WHERE sls_order_dt <= 0 OR LEN(sls_order_dt) != 8 
OR sls_order_dt > 20500101 OR sls_order_dt < 19000101
-- Check the same way for sls_ship_dt and sls_due_dt

-- Check for Invalid Date Orders
SELECT *
FROM [DataWarehouse].[bronze].[crm_sales_details]
--WHERE sls_order_dt > sls_ship_dt OR sls_order_dt > sls_due_dt

-- Check Data Consistency: Between Sales, Quantity and Price
-- Sales = Quantity * Price
-- Values must not be NULL, zero or negative
SELECT DISTINCT sls_sales, sls_quantity, sls_price
FROM [DataWarehouse].[bronze].[crm_sales_details]
WHERE sls_sales != sls_quantity * sls_price
OR sls_sales IS NULL OR sls_quantity IS NULL OR sls_price IS NULL
OR sls_sales <= 0 OR sls_quantity <= 0 OR sls_price <= 0
ORDER BY sls_sales, sls_quantity, sls_price

SELECT *
FROM [silver].[crm_sales_details]

--	TABLE ERP.CUST_AZ12
-- Check whether cids from table erp.cust_az12 are present in column cst_key of table crm.cust_info
SELECT 
	CASE WHEN cid LIKE 'NAS%' THEN SUBSTRING(cid, 4, LEN(cid))
		 ELSE cid
	END AS cid,
	bdate,
	gen
FROM [DataWarehouse].[bronze].[erp_cust_az12]
WHERE CASE WHEN cid LIKE 'NAS%' THEN SUBSTRING(cid, 4, LEN(cid))
		 ELSE cid
	END NOT IN (SELECT DISTINCT cst_key FROM silver.crm_cust_info)

-- Check for Out-of-range Dates
SELECT DISTINCT bdate
FROM [DataWarehouse].[bronze].[erp_cust_az12]
WHERE bdate < '1924-01-01' OR bdate > GETDATE()

-- Data Standardization and Consisitency
SELECT DISTINCT gen
FROM [DataWarehouse].[bronze].[erp_cust_az12]

SELECT * 
FROM [DataWarehouse].[silver].[erp_cust_az12]

--	TABLE ERP.LOC_A101
-- Check for consistency in values between cst_key from crm.cust_info and cid from erp.loc_a101
SELECT REPLACE(cid, '-', '') AS cid
FROM [DataWarehouse].[bronze].[erp_loc_a101]
WHERE REPLACE(cid, '-', '') NOT IN (SELECT DISTINCT cst_key FROM silver.crm_cust_info)

-- Data Standardization and Consistency
SELECT DISTINCT cntry 
FROM [DataWarehouse].[bronze].[erp_loc_a101]

--	TABLE ERP.PX_CAT_G1V2
-- Check for consistency in values between id from erp.px_cat_g1v2 and prd_key from crm.prd_info
SELECT * 
FROM [silver].[crm_prd_info]

SELECT * 
FROM [DataWarehouse].[bronze].[erp_px_cat_g1v2];

-- Check for unwanted spaces
SELECT *
FROM [DataWarehouse].[bronze].[erp_px_cat_g1v2]
WHERE cat != TRIM(cat)
-- Also check for subcat and maintenance

-- Data Standardization and Consistency
SELECT DISTINCT cat
FROM [DataWarehouse].[bronze].[erp_px_cat_g1v2]
-- Also check for subcat and maintenance
