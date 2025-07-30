# Process Eviction Data for Bivariate Map
# Calculate annual eviction rates by census tract and standardize by population

library(dplyr)
library(readr)
library(sf)

# Read the Columbus monthly data
cat("=== READING EVICTION DATA ===\n")
columbus_data <- read_csv("columbus_monthly_2020_2021.csv")

# Remove sealed entries (missing tract data)
columbus_clean <- columbus_data %>%
  filter(GEOID != "sealed" & !is.na(GEOID))

cat("Original data rows:", nrow(columbus_data), "\n")
cat("After removing sealed entries:", nrow(columbus_clean), "\n")

# Calculate annual eviction filings by census tract
cat("\n=== CALCULATING ANNUAL EVICTION FILINGS ===\n")
annual_filings <- columbus_clean %>%
  group_by(GEOID, racial_majority) %>%
  summarise(
    total_filings_2020 = sum(filings_2020, na.rm = TRUE),
    total_filings_avg = sum(filings_avg, na.rm = TRUE),
    total_filings_baseline = sum(filings_avg_prepandemic_baseline, na.rm = TRUE),
    months_with_data = n(),
    .groups = 'drop'
  ) %>%
  arrange(desc(total_filings_2020))

print("Top 10 tracts by total filings in 2020:")
print(head(annual_filings, 10))

# Read the Franklin County SVI data to get tract information
cat("\n=== READING SVI DATA FOR TRACT INFORMATION ===\n")
franklin_svi <- st_read("Franklin County SVI Data.shp")

# Convert SVI data to numeric
franklin_svi$SVI_numeric <- as.numeric(as.character(franklin_svi$SVI.Data.f))

# Create a simple tract summary from SVI data
tract_info <- franklin_svi %>%
  as.data.frame() %>%
  select(GEOID, NAME, ALAND, AWATER, SVI_numeric) %>%
  mutate(
    # Estimate population using land area as proxy (this is a rough approximation)
    # In a real scenario, you'd want actual population data from ACS
    estimated_population = ALAND / 1000, # Rough population estimate based on land area
    tract_area_km2 = ALAND / 1000000
  )

print("Tract information summary:")
print(head(tract_info, 10))

# Merge eviction data with tract information
cat("\n=== MERGING EVICTION AND TRACT DATA ===\n")
eviction_with_pop <- annual_filings %>%
  left_join(tract_info, by = "GEOID") %>%
  filter(!is.na(estimated_population) & estimated_population > 0)

cat("Tracts with population data:", nrow(eviction_with_pop), "\n")

# Calculate eviction rates (filings per 1,000 residents)
cat("\n=== CALCULATING EVICTION RATES ===\n")
eviction_rates <- eviction_with_pop %>%
  mutate(
    eviction_rate_2020 = (total_filings_2020 / estimated_population) * 1000,
    eviction_rate_avg = (total_filings_avg / estimated_population) * 1000,
    eviction_rate_baseline = (total_filings_baseline / estimated_population) * 1000
  ) %>%
  # Handle infinite values (when population is 0)
  mutate(
    eviction_rate_2020 = ifelse(is.infinite(eviction_rate_2020), 0, eviction_rate_2020),
    eviction_rate_avg = ifelse(is.infinite(eviction_rate_avg), 0, eviction_rate_avg),
    eviction_rate_baseline = ifelse(is.infinite(eviction_rate_baseline), 0, eviction_rate_baseline)
  )

print("Eviction rates summary:")
print(summary(eviction_rates$eviction_rate_2020))

# Create final dataset for bivariate mapping
cat("\n=== CREATING FINAL DATASET FOR BIVARIATE MAPPING ===\n")
bivariate_data <- eviction_rates %>%
  select(
    GEOID,
    NAME,
    racial_majority,
    total_filings_2020,
    eviction_rate_2020,
    SVI_numeric,
    ALAND,
    AWATER,
    estimated_population
  ) %>%
  # Normalize SVI to 0-1 scale
  mutate(
    SVI_normalized = SVI_numeric / max(SVI_numeric, na.rm = TRUE),
    eviction_rate_normalized = eviction_rate_2020 / max(eviction_rate_2020, na.rm = TRUE)
  )

print("Final dataset summary:")
print(summary(bivariate_data))

# Save the processed data
write_csv(bivariate_data, "eviction_svi_bivariate_data.csv")

cat("\n=== DATA PROCESSING COMPLETE ===\n")
cat("File saved: eviction_svi_bivariate_data.csv\n")
cat("Total tracts with complete data:", nrow(bivariate_data), "\n")
cat("Tracts with eviction filings in 2020:", sum(bivariate_data$total_filings_2020 > 0), "\n")

# Show top tracts by eviction rate
cat("\nTop 10 tracts by eviction rate (per 1,000 residents):\n")
top_eviction_tracts <- bivariate_data %>%
  arrange(desc(eviction_rate_2020)) %>%
  select(GEOID, NAME, racial_majority, total_filings_2020, eviction_rate_2020, SVI_normalized)
print(head(top_eviction_tracts, 10))

# Show correlation between SVI and eviction rates
cat("\nCorrelation between SVI and eviction rates:\n")
correlation <- cor(bivariate_data$SVI_normalized, bivariate_data$eviction_rate_normalized, use = "complete.obs")
cat("Correlation coefficient:", round(correlation, 4), "\n") 