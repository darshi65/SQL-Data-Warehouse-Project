-- Adding column cat_id to bronze.crm_prd_info
ALTER TABLE [DataWarehouse].[bronze].[crm_prd_info]
ADD cat_id NVARCHAR (50);

UPDATE [DataWarehouse].[bronze].[crm_prd_info]
SET cat_id = prd_key;

-- Extracting the id from cat_id to make it easier to join with table erp.px_cat_g1v2
-- Subsituting '-' in cat_id with '_' to ensure consistency with table erp.px_cat_g1v2
UPDATE [DataWarehouse].[bronze].[crm_prd_info]
SET cat_id = REPLACE(SUBSTRING(cat_id, 1, 5), '-', '_');

EXEC silver.load_silver

CREATE OR ALTER PROCEDURE silver.load_silver AS 
BEGIN
    DECLARE @start_time DATETIME, @end_time DATETIME, @batch_start_time DATETIME, @batch_end_time DATETIME;
	BEGIN TRY
	SET @batch_start_time = GETDATE();
        PRINT '==== Loading Silver Layer ===='

		PRINT '---- Loading CRM Tables ----'

		SET @start_time = GETDATE();
		PRINT '>> Truncating Table: silver.crm_cust_info'
		TRUNCATE TABLE [DataWarehouse].[silver].[crm_cust_info]
		 --Emptying the table everytime a new session is started to avoid re-adding the data into the tables

		PRINT '>> Inserting Data Into:silver.crm_cust_info'

        -- Removing the duplicates
        -- Removing NULL values
        -- Removing unwanted spaces
        -- Converting short forms to full-forms (M -> Male)
        INSERT INTO [DataWarehouse].[silver].[crm_cust_info] (
            [cst_id], 
            [cst_key], 
            [cst_firstname], 
            [cst_lastname], 
            [cst_marital_status], 
            [cst_gndr], 
            [cst_create_date]
        )
        SELECT cst_id,
               cst_key,
               TRIM(cst_firstname) AS cst_firstname,
               TRIM(cst_lastname) AS cst_lastname,
               CASE WHEN UPPER(TRIM(cst_marital_status)) = 'S' THEN 'Single' WHEN UPPER(TRIM(cst_marital_status)) = 'M' THEN 'Married' ELSE 'N/A' END AS cst_marital_status,
               CASE WHEN UPPER(TRIM(cst_gndr)) = 'F' THEN 'Female' WHEN UPPER(TRIM(cst_gndr)) = 'M' THEN 'Male' ELSE 'N/A' END AS cst_gndr,
               cst_create_date
        FROM   (SELECT *,
                       ROW_NUMBER() OVER (PARTITION BY cst_id ORDER BY cst_create_date DESC) AS flag_last
                FROM   [DataWarehouse].[bronze].[crm_cust_info]
                WHERE  cst_id IS NOT NULL) AS t
        WHERE  flag_last = 1;

        SET @end_time = GETDATE();
		PRINT '>> Load Duration: ' + CAST(DATEDIFF(second, @start_time, @end_time) AS NVARCHAR) + ' seconds';

        -- TABLE CRM.PRD_INFO --
        
		SET @start_time = GETDATE();
		PRINT '>> Truncating Table: silver.crm_prd_info'
		TRUNCATE TABLE [silver].[crm_prd_info]

		PRINT '>> Inserting Data Into: silver.crm_prd_info'

        -- Extracting the sls_prd_key from prd_key to make it easier to join with table crm.sales_details
        -- Removing NULL values from prd_cost
        -- Converting short forms to full-forms 
        INSERT INTO [silver].[crm_prd_info] (
            [prd_id], 
            [cat_id], 
            [prd_key], 
            [prd_nm], 
            [prd_cost], 
            [prd_line], 
            [prd_start_dt], 
            [prd_end_dt])
        SELECT 
            prd_id,
            cat_id,
            SUBSTRING(prd_key, 7, LEN(prd_key)) AS prd_key,
            prd_nm,
            ISNULL(prd_cost, 0) AS prd_cost,
            CASE UPPER(TRIM(prd_line)) 
                WHEN 'R' THEN 'Road' 
                WHEN 'M' THEN 'Mountain' 
                WHEN 'S' THEN 'Other Sales' 
                WHEN 'T' THEN 'Touring' ELSE 'N/A' 
            END AS prd_line,
            CAST (prd_start_dt AS DATE) AS prd_start_dt,
            CAST (LEAD(prd_start_dt) OVER (PARTITION BY prd_key ORDER BY prd_start_dt) - 1 AS DATE) AS prd_end_dt
        FROM [DataWarehouse].[bronze].[crm_prd_info];

        SET @end_time = GETDATE();
		PRINT '>> Load Duration: ' + CAST(DATEDIFF(second, @start_time, @end_time) AS NVARCHAR) + ' seconds';

        -- TABLE CRM.SALES_DETAILS --

		SET @start_time = GETDATE();
		PRINT '>> Truncating Table: silver.crm_sales_details'
		TRUNCATE TABLE [silver].[crm_sales_details]

		PRINT '>> Inserting Data Into: silver.crm_sales_details'
        -- Formatted the date
        -- Rectified invalid date orders
        -- Standardized the price, quantity and sales by removing NULLs, zeros and negative values
        INSERT INTO [silver].[crm_sales_details] (
            sls_ord_num, 
            sls_prd_key, 
            sls_cust_id, 
            sls_order_dt, 
            sls_ship_dt, 
            sls_due_dt, 
            sls_sales, 
            sls_quantity, 
            sls_price)
        SELECT 
            sls_ord_num,
            sls_prd_key,
            sls_cust_id,
            CASE WHEN sls_order_dt = 0 OR LEN(sls_order_dt) != 8 THEN NULL 
                ELSE CAST (CAST (sls_order_dt AS VARCHAR) AS DATE) 
            END AS sls_order_dt,
            CASE WHEN sls_ship_dt = 0 OR LEN(sls_ship_dt) != 8 THEN NULL 
                ELSE CAST (CAST (sls_ship_dt AS VARCHAR) AS DATE) 
            END AS sls_ship_dt,
            CASE WHEN sls_due_dt = 0 OR LEN(sls_due_dt) != 8 THEN NULL 
                ELSE CAST (CAST (sls_due_dt AS VARCHAR) AS DATE) 
            END AS sls_due_dt,
            CASE WHEN sls_sales IS NULL OR sls_sales <= 0 OR sls_sales != sls_quantity * ABS(sls_price) 
                THEN sls_quantity * ABS(sls_price) 
                ELSE sls_sales 
            END AS sls_sales,
            sls_quantity,
            CASE WHEN sls_price IS NULL OR sls_price <= 0 THEN sls_sales / NULLIF (sls_quantity, 0) 
                ELSE sls_price 
            END AS sls_price
        FROM   [DataWarehouse].[bronze].[crm_sales_details];

        SET @end_time = GETDATE();
		PRINT '>> Load Duration: ' + CAST(DATEDIFF(second, @start_time, @end_time) AS NVARCHAR) + ' seconds';

        -- TABLE ERP.CUST_AZ12 --

        PRINT '---- Loading ERP Tables ----'

        SET @start_time = GETDATE();
		PRINT '>> Truncating Table: silver.erp_cust_az12'
		TRUNCATE TABLE [DataWarehouse].[silver].[erp_cust_az12]

		PRINT '>> Inserting Data Into: silver.erp_cust_az12'
		 -- Extracting the cst_key from cid to make it easier to join with table crm.cust_info
        -- Replacing wildly inaccurate or future dates with NULLs
        -- Standardizing gender values 
        INSERT INTO [DataWarehouse].[silver].[erp_cust_az12] (cid, bdate, gen)
        SELECT CASE WHEN cid LIKE 'NAS%' THEN SUBSTRING(cid, 4, LEN(cid)) ELSE cid END AS cid,
               CASE WHEN bdate > GETDATE() THEN NULL ELSE bdate END AS bdate,
               CASE WHEN UPPER(TRIM(gen)) IN ('F', 'FEMALE') THEN 'Female' WHEN UPPER(TRIM(gen)) IN ('M', 'MALE') THEN 'Male' ELSE 'N/A' END AS gen
        FROM   [DataWarehouse].[bronze].[erp_cust_az12];

        SET @end_time = GETDATE();
		PRINT '>> Load Duration: ' + CAST(DATEDIFF(second, @start_time, @end_time) AS NVARCHAR) + ' seconds';

        -- TABLE ERP.LOC_101 --

        SET @start_time = GETDATE();
		PRINT '>> Truncating Table: silver.erp_loc_a101'
		TRUNCATE TABLE [DataWarehouse].[silver].[erp_loc_a101]

		PRINT '>> Inserting Data Into: silver.erp_loc_a101'
        -- Removing extra characters to match the cst_key from crm_cust_info table
        -- Standardize the countries
        INSERT INTO [DataWarehouse].[silver].[erp_loc_a101] (cid, cntry)
        SELECT 
            REPLACE(cid, '-', '') AS cid,
            CASE WHEN TRIM(cntry) = 'DE' THEN 'Germany' 
                 WHEN TRIM(cntry) IN ('US', 'USA') THEN 'United States' 
                 WHEN TRIM(cntry) = '' OR cntry IS NULL THEN 'N/A'
                 ELSE TRIM(cntry)
            END AS cntry
        FROM [DataWarehouse].[bronze].[erp_loc_a101];

        SET @end_time = GETDATE();
		PRINT '>> Load Duration: ' + CAST(DATEDIFF(second, @start_time, @end_time) AS NVARCHAR) + ' seconds';

        -- TABLE ERP.PX_CAT_G1V2 --

        SET @start_time = GETDATE();
		PRINT '>> Truncating Table: silver.erp_px_cat_g1v2'
		TRUNCATE TABLE [DataWarehouse].[silver].[erp_px_cat_g1v2]
	
		PRINT '>> Inserting Data Into: silver.erp_px_cat_g1v2'

        INSERT INTO [DataWarehouse].[silver].[erp_px_cat_g1v2] (id, cat, subcat, maintenance)
        SELECT id,
               cat,
               subcat,
               maintenance
        FROM [DataWarehouse].[bronze].[erp_px_cat_g1v2];

        SET @end_time = GETDATE();
		PRINT '>> Load Duration: ' + CAST(DATEDIFF(second, @start_time, @end_time) AS NVARCHAR) + ' seconds';

        SET @batch_end_time = GETDATE();

		PRINT '==== Loading Silver Layer is Completed ===='
		PRINT '   - Total Load Duration: ' + CAST(DATEDIFF(second, @batch_start_time, @batch_end_time) AS NVARCHAR) + ' seconds';

	END TRY  -- Error handling
	BEGIN CATCH 
		PRINT '==== ERROR OCCURED DURING LOADING SILVER LAYER ===='
		PRINT 'Error Message: ' + ERROR_MESSAGE();
		PRINT 'Error Message ' + CAST (ERROR_NUMBER() AS NVARCHAR);
		PRINT 'Error Message ' + CAST (ERROR_STATE() AS NVARCHAR);
	END CATCH      
END