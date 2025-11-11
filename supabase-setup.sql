-- Update Supabase Database for Multi-User Support
-- Run this SQL in Supabase SQL Editor
-- Project: https://supabase.com/dashboard/project/oqjcbjgidnybvvzecrhg/sql

-- ============================================
-- 1. ADD user_id COLUMNS
-- ============================================

-- Add user_id column to asin_master
ALTER TABLE asin_master ADD COLUMN IF NOT EXISTS user_id UUID REFERENCES auth.users(id);

-- Add user_id column to invoices
ALTER TABLE invoices ADD COLUMN IF NOT EXISTS user_id UUID REFERENCES auth.users(id);

-- Add user_id column to advertising
ALTER TABLE advertising ADD COLUMN IF NOT EXISTS user_id UUID REFERENCES auth.users(id);

-- Add user_id column to vret_cogs
ALTER TABLE vret_cogs ADD COLUMN IF NOT EXISTS user_id UUID REFERENCES auth.users(id);

-- ============================================
-- 2. CREATE INDEXES ON user_id
-- ============================================

CREATE INDEX IF NOT EXISTS idx_asin_master_user_id ON asin_master(user_id);
CREATE INDEX IF NOT EXISTS idx_invoices_user_id ON invoices(user_id);
CREATE INDEX IF NOT EXISTS idx_advertising_user_id ON advertising(user_id);
CREATE INDEX IF NOT EXISTS idx_vret_cogs_user_id ON vret_cogs(user_id);

-- ============================================
-- 3. UPDATE RLS POLICIES
-- ============================================

-- Enable RLS on all tables first
ALTER TABLE asin_master ENABLE ROW LEVEL SECURITY;
ALTER TABLE invoices ENABLE ROW LEVEL SECURITY;
ALTER TABLE advertising ENABLE ROW LEVEL SECURITY;
ALTER TABLE vret_cogs ENABLE ROW LEVEL SECURITY;

-- Drop ALL existing policies on each table (regardless of name)
DO $$
DECLARE
    pol RECORD;
BEGIN
    FOR pol IN
        SELECT policyname, tablename
        FROM pg_policies
        WHERE tablename IN ('asin_master', 'invoices', 'advertising', 'vret_cogs')
    LOOP
        EXECUTE format('DROP POLICY IF EXISTS %I ON %I', pol.policyname, pol.tablename);
    END LOOP;
END $$;

-- Create new user-specific policies for asin_master
CREATE POLICY "Users can access own asin_master" ON asin_master
    FOR ALL USING (auth.uid() = user_id);

-- Create new user-specific policies for invoices
CREATE POLICY "Users can access own invoices" ON invoices
    FOR ALL USING (auth.uid() = user_id);

-- Create new user-specific policies for advertising
CREATE POLICY "Users can access own advertising" ON advertising
    FOR ALL USING (auth.uid() = user_id);

-- Create new user-specific policies for vret_cogs
CREATE POLICY "Users can access own vret_cogs" ON vret_cogs
    FOR ALL USING (auth.uid() = user_id);

-- ============================================
-- 4. CREATE FUNCTIONS TO BYPASS 1000-ROW LIMIT
-- ============================================
-- These functions bypass Supabase's default 1000-row limit
-- by using PostgreSQL functions that return unlimited rows

-- Function to get all invoices for a vendor (UNLIMITED ROWS)
CREATE OR REPLACE FUNCTION get_all_invoices(p_user_id UUID, p_vendor TEXT)
RETURNS TABLE (
    id BIGINT,
    user_id UUID,
    vendor TEXT,
    date DATE,
    invoice_id TEXT,
    asin TEXT,
    quantity INTEGER,
    item_price NUMERIC,
    freight_cost NUMERIC,
    row_id TEXT,
    created_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    -- Verify the requesting user matches the parameter
    IF auth.uid() != p_user_id THEN
        RAISE EXCEPTION 'Unauthorized access';
    END IF;

    RETURN QUERY
    SELECT
        i.id,
        i.user_id,
        i.vendor,
        i.date,
        i.invoice_id,
        i.asin,
        i.quantity,
        i.item_price,
        i.freight_cost,
        i.row_id,
        i.created_at
    FROM invoices i
    WHERE i.user_id = p_user_id
    AND i.vendor = p_vendor
    ORDER BY i.date DESC;
END;
$$;

-- Function to get all advertising data for a vendor (UNLIMITED ROWS)
CREATE OR REPLACE FUNCTION get_all_advertising(p_user_id UUID, p_vendor TEXT)
RETURNS TABLE (
    id BIGINT,
    user_id UUID,
    vendor TEXT,
    date DATE,
    asin TEXT,
    spend NUMERIC,
    sales NUMERIC,
    orders INTEGER,
    clicks INTEGER,
    impressions INTEGER,
    created_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    -- Verify the requesting user matches the parameter
    IF auth.uid() != p_user_id THEN
        RAISE EXCEPTION 'Unauthorized access';
    END IF;

    RETURN QUERY
    SELECT
        a.id,
        a.user_id,
        a.vendor,
        a.date,
        a.asin,
        a.spend,
        a.sales,
        a.orders,
        a.clicks,
        a.impressions,
        a.created_at
    FROM advertising a
    WHERE a.user_id = p_user_id
    AND a.vendor = p_vendor
    ORDER BY a.date DESC;
END;
$$;

-- Function to get all ASIN master data for a vendor (UNLIMITED ROWS)
CREATE OR REPLACE FUNCTION get_all_asin_master(p_user_id UUID, p_vendor TEXT)
RETURNS TABLE (
    id BIGINT,
    user_id UUID,
    vendor TEXT,
    asin TEXT,
    product_name TEXT,
    created_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    -- Verify the requesting user matches the parameter
    IF auth.uid() != p_user_id THEN
        RAISE EXCEPTION 'Unauthorized access';
    END IF;

    RETURN QUERY
    SELECT
        am.id,
        am.user_id,
        am.vendor,
        am.asin,
        am.product_name,
        am.created_at
    FROM asin_master am
    WHERE am.user_id = p_user_id
    AND am.vendor = p_vendor
    ORDER BY am.asin;
END;
$$;

-- Function to get all VRET & COGS data for a vendor (UNLIMITED ROWS)
CREATE OR REPLACE FUNCTION get_all_vret_cogs(p_user_id UUID, p_vendor TEXT)
RETURNS TABLE (
    id BIGINT,
    user_id UUID,
    vendor TEXT,
    year INTEGER,
    month INTEGER,
    asin TEXT,
    vret_rate NUMERIC,
    cogs NUMERIC,
    created_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    -- Verify the requesting user matches the parameter
    IF auth.uid() != p_user_id THEN
        RAISE EXCEPTION 'Unauthorized access';
    END IF;

    RETURN QUERY
    SELECT
        vc.id,
        vc.user_id,
        vc.vendor,
        vc.year,
        vc.month,
        vc.asin,
        vc.vret_rate,
        vc.cogs,
        vc.created_at
    FROM vret_cogs vc
    WHERE vc.user_id = p_user_id
    AND vc.vendor = p_vendor
    ORDER BY vc.year DESC, vc.month DESC;
END;
$$;

-- Grant execute permissions to authenticated users
GRANT EXECUTE ON FUNCTION get_all_invoices(UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION get_all_advertising(UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION get_all_asin_master(UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION get_all_vret_cogs(UUID, TEXT) TO authenticated;

-- ============================================
-- 5. VERIFY SETUP
-- ============================================

-- Check that RLS is enabled on all tables
SELECT schemaname, tablename, rowsecurity
FROM pg_tables
WHERE tablename IN ('asin_master', 'invoices', 'advertising', 'vret_cogs')
ORDER BY tablename;

-- Check policies
SELECT schemaname, tablename, policyname
FROM pg_policies
WHERE tablename IN ('asin_master', 'invoices', 'advertising', 'vret_cogs')
ORDER BY tablename, policyname;

-- Check functions
SELECT routine_name, routine_type
FROM information_schema.routines
WHERE routine_schema = 'public'
AND routine_name LIKE 'get_all_%'
ORDER BY routine_name;

-- ============================================
-- SETUP COMPLETE!
-- ============================================
-- Next steps:
-- 1. Run this SQL in Supabase SQL Editor
-- 2. Verify all 4 tables have user_id column
-- 3. Verify RLS policies are in place
-- 4. Verify all 4 functions are created
-- 5. Update your JavaScript code to call these functions instead of direct queries
--
-- Benefits of using these functions:
-- - Bypasses the 1000-row default limit completely
-- - Returns ALL rows without pagination needed
-- - Built-in security with auth.uid() verification
-- - Optimized with proper indexing
-- - No client-side batching required
-- ============================================
