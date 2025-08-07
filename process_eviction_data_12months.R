# Process eviction data for 12-month period
# July 2024 - June 2025

library(dplyr)
library(readr)
library(sf)

columbus_data <- read_csv("columbus_monthly_2020_2021.csv") #load and clean data
columbus_clean <- columbus_data %>% 
  filter(GEOID != "sealed" & !is.na(GEOID)) %>%
  mutate(GEOID = as.character(GEOID))

columbus_clean <- columbus_clean %>% #convert dates
  mutate(
    month_year = paste0(month, "-01"),
    date = as.Date(month_year, format = "%b-%y-%d")
  )

start_date <- as.Date("2024-07-01")
end_date <- as.Date("2025-06-30")

recent_data <- columbus_clean %>%
  filter(date >= start_date & date <= end_date)

eviction_12months <- recent_data %>% #sum filings by tract
  group_by(GEOID, racial_majority) %>%
  summarise(
    total_filings_12months = sum(filings_2020, na.rm = TRUE),
    .groups = 'drop'
  )

franklin_svi <- st_read("Franklin County SVI Data.shp")
franklin_svi$GEOID <- as.character(franklin_svi$GEOID)

tract_info <- franklin_svi %>%
  as.data.frame() %>%
  select(GEOID, NAME, ALAND, AWATER, SVI.Data.f) %>%
  mutate(
    estimated_population = ALAND / 1000,
    tract_area_km2 = ALAND / 1000000,
    SVI_numeric = as.numeric(as.character(SVI.Data.f))
  )

eviction_with_pop <- eviction_12months %>% #merge data
  left_join(tract_info, by = "GEOID") %>%
  filter(!is.na(estimated_population) & estimated_population > 0)

eviction_rates_12months <- eviction_with_pop %>%
  mutate(
    eviction_rate_12months = (total_filings_12months / estimated_population) * 1000,
    eviction_rate_12months = ifelse(is.infinite(eviction_rate_12months), 0, eviction_rate_12months)
  )

bivariate_data_12months <- eviction_rates_12months %>%
  select(GEOID, NAME, racial_majority, total_filings_12months, eviction_rate_12months, 
         SVI_numeric, ALAND, AWATER, estimated_population) %>%
  mutate(
    SVI_normalized = SVI_numeric / max(SVI_numeric, na.rm = TRUE),
    eviction_rate_normalized = eviction_rate_12months / max(eviction_rate_12months, na.rm = TRUE)
  )

write_csv(bivariate_data_12months, "eviction_svi_bivariate_data_12months.csv")

#Print summary
cat("=== 12-Month Eviction Analysis (July 2024 - June 2025) ===\n")
cat("Total census tracts with data:", nrow(bivariate_data_12months), "\n")
cat("Total eviction filings across all tracts:", sum(bivariate_data_12months$total_filings_12months), "\n")
cat("Average eviction rate per 1,000 residents:", mean(bivariate_data_12months$eviction_rate_12months, na.rm = TRUE), "\n")
cat("Median eviction rate per 1,000 residents:", median(bivariate_data_12months$eviction_rate_12months, na.rm = TRUE), "\n")
cat("Maximum eviction rate per 1,000 residents:", max(bivariate_data_12months$eviction_rate_12months, na.rm = TRUE), "\n")

cat("\n=== Top 10 Census Tracts by Eviction Filings (Past 12 Months) ===\n")
top_tracts <- bivariate_data_12months %>%
  arrange(desc(total_filings_12months)) %>%
  select(NAME, total_filings_12months, eviction_rate_12months, racial_majority) %>%
  head(10)

print(top_tracts) 