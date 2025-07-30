# Process Eviction Data for Past 12 Months (June 2025)
# Calculate total eviction filings from July 2024 to June 2025

library(dplyr)
library(readr)
library(sf)

# Load the eviction data
columbus_data <- read_csv("columbus_monthly_2020_2021.csv")

# Clean the data - remove "sealed" entries and convert GEOID to character
columbus_clean <- columbus_data %>% 
  filter(GEOID != "sealed" & !is.na(GEOID)) %>%
  mutate(GEOID = as.character(GEOID))

# Define the 12-month period: July 2024 to June 2025
# Convert month-year to date for easier filtering
columbus_clean <- columbus_clean %>%
  mutate(
    # Parse month and year from the month column
    month_year = paste0(month, "-01"),
    date = as.Date(month_year, format = "%b-%y-%d")
  )

# Filter for the past 12 months from June 2025
# June 2025 would be the current month, so we want July 2024 to June 2025
start_date <- as.Date("2024-07-01")
end_date <- as.Date("2025-06-30")

# Filter data for the 12-month period
recent_data <- columbus_clean %>%
  filter(date >= start_date & date <= end_date)

# Sum eviction filings by census tract for the past 12 months
eviction_12months <- recent_data %>%
  group_by(GEOID, racial_majority) %>%
  summarise(
    total_filings_12months = sum(filings_2020, na.rm = TRUE),
    .groups = 'drop'
  )

# Load the shapefile data for population estimates
franklin_svi <- st_read("Franklin County SVI Data.shp")
franklin_svi$GEOID <- as.character(franklin_svi$GEOID)

# Get tract information for population estimates
tract_info <- franklin_svi %>%
  as.data.frame() %>%
  select(GEOID, NAME, ALAND, AWATER, SVI.Data.f) %>%
  mutate(
    estimated_population = ALAND / 1000,  # Use land area as proxy for population
    tract_area_km2 = ALAND / 1000000,
    SVI_numeric = as.numeric(as.character(SVI.Data.f))
  )

# Merge eviction data with tract information
eviction_with_pop <- eviction_12months %>%
  left_join(tract_info, by = "GEOID") %>%
  filter(!is.na(estimated_population) & estimated_population > 0)

# Calculate eviction rate per 1,000 residents for the past 12 months
eviction_rates_12months <- eviction_with_pop %>%
  mutate(
    eviction_rate_12months = (total_filings_12months / estimated_population) * 1000,
    eviction_rate_12months = ifelse(is.infinite(eviction_rate_12months), 0, eviction_rate_12months)
  )

# Create normalized values for mapping
bivariate_data_12months <- eviction_rates_12months %>%
  select(GEOID, NAME, racial_majority, total_filings_12months, eviction_rate_12months, 
         SVI_numeric, ALAND, AWATER, estimated_population) %>%
  mutate(
    SVI_normalized = SVI_numeric / max(SVI_numeric, na.rm = TRUE),
    eviction_rate_normalized = eviction_rate_12months / max(eviction_rate_12months, na.rm = TRUE)
  )

# Save the processed data
write_csv(bivariate_data_12months, "eviction_svi_bivariate_data_12months.csv")

# Print summary statistics
cat("=== 12-Month Eviction Analysis (July 2024 - June 2025) ===\n")
cat("Total census tracts with data:", nrow(bivariate_data_12months), "\n")
cat("Total eviction filings across all tracts:", sum(bivariate_data_12months$total_filings_12months), "\n")
cat("Average eviction rate per 1,000 residents:", mean(bivariate_data_12months$eviction_rate_12months, na.rm = TRUE), "\n")
cat("Median eviction rate per 1,000 residents:", median(bivariate_data_12months$eviction_rate_12months, na.rm = TRUE), "\n")
cat("Maximum eviction rate per 1,000 residents:", max(bivariate_data_12months$eviction_rate_12months, na.rm = TRUE), "\n")

# Show top 10 tracts by eviction filings
cat("\n=== Top 10 Census Tracts by Eviction Filings (Past 12 Months) ===\n")
top_tracts <- bivariate_data_12months %>%
  arrange(desc(total_filings_12months)) %>%
  select(NAME, total_filings_12months, eviction_rate_12months, racial_majority) %>%
  head(10)

print(top_tracts) 