# Franklin County Eviction & Social Vulnerability Analysis

![Bivariate Map of Franklin County Eviction and Social Vulnerability Analysis](images/Screenshot.png)

## Overview

This project creates an interactive bivariate map showing eviction rates (per 1,000 residents) and Social Vulnerability Index (SVI) data for Franklin County, Ohio census tracts. The application allows users to explore the spatial distribution of eviction activity and its relationship to social vulnerability factors, providing a tool for identifying high-risk areas and planning community interventions.

**This is a work in progress project.** The analysis and application are being actively developed and refined.

Created by Samyak Shrestha | Mentored by Dr. Ayaz Hyder and Special thanks to Dylan Sansone and the Smart Columbus Team!

## Impact on Community Interventions

This analysis provides insights for organizations like Smart Columbus and other nonprofits working to address housing instability and homelessness prevention. By identifying census tracts with high eviction rates combined with high social vulnerability, these organizations can:

- Focus resources on areas with both high eviction rates and high SVI scores to maximize impact.
- Use spatial data to guide program design and identify opportunities for collaborative service delivery.
- Deploy proactive interventions like legal aid, rental assistance, and tenant education in high-risk communities.
- Support policy, advocacy, and grant applications with clear, data-driven evidence of need and changing conditions.
- Prioritize interventions based on standardized eviction rates that account for population size differences.


## Features

- **Interactive Bivariate Mapping**: Visualize eviction rates (per 1,000 residents) and SVI data simultaneously
- **Multiple View Modes**: Switch between bivariate, SVI-only, or eviction rate views
- **Population Data Integration**: U.S. Census Bureau ACS 5-Year Estimates (2023) for all 328 census tracts
- **Enhanced Popups**: Display both eviction filings count AND eviction rate per 1,000 residents
- **Comprehensive Statistics**: Population statistics, eviction rate statistics, and SVI statistics
- **Nonprofit Layer**: Toggle to show nonprofit organization locations across Franklin County
- **Real-time Statistics**: Statistics panel showing key metrics including nonprofit count
- **Hover Information**: Detailed popups with tract-specific information and nonprofit details
- **Layer Controls**: Multiple map tile options (Light, Street, Satellite)
- **Risk Classification**: Color-coded bivariate classification with red indicating highest urgency areas

## Data Sources

### Eviction Data
- **Source**: Franklin County Court System
- **Coverage**: Franklin County, Ohio monthly eviction filings
- **Time Period**: July 2024 - June 2025 (12 months)
- **Processing**: Aggregated by census tract and converted to rates per 1,000 residents

### Social Vulnerability Index (SVI)
- **Source**: CDC/ATSDR Social Vulnerability Index
- **Coverage**: Franklin County, Ohio

### Population Data
- **Source**: U.S. Census Bureau American Community Survey (ACS)
- **Coverage**: 5-Year Estimates (2019-2023)
- **Geographic Unit**: Census Tract level
- **File**: `ACSDT5Y2023.B01003-Data.csv`

### Geographic Data
- **Source**: Franklin County SVI Data (ESRI Shapefile)
- **Coverage**: Franklin County census tracts

## Data Limitations 

This analysis captures eviction court filings (not actual evictions) and uses SVI as a composite vulnerability measure. The temporal gap between 2022 SVI data and 2024-2025 eviction data can reveal areas where recent patterns differ from historical vulnerability trends, indicating emerging risks or successful interventions. The bivariate classification uses relative thresholds based on median values and shows spatial relationships rather than causal connections. 

The analysis now includes population data to calculate standardized eviction rates per 1,000 residents, eliminating bias from tract size differences. Use this analysis alongside local knowledge and additional data sources for comprehensive community planning.

## Installation & Setup

### Prerequisites
- R (version 4.0 or higher)
- RStudio (recommended)

### Required R Packages
```r
install.packages(c(
  "shiny",
  "sf", 
  "leaflet",
  "dplyr",
  "readr",
  "RColorBrewer"
))
```

### Data Files Required
1. `data/processed/eviction_svi_bivariate_data_12months.csv` - Processed eviction and SVI data
2. `data/raw/Franklin County SVI Data.shp` - Shapefile with tract boundaries and SVI data
3. `ACSDT5Y2023.B01003-Data.csv` - U.S. Census Bureau population data
4. `nonprofits_mapped/nonprofit_final_to_geocode.shp` - Nonprofit organization locations
5. `data_dictionary.csv` - Comprehensive data dictionary for all variables

## Usage

### Running the Application

1. **Process the data** (first time only):
   ```r
   source("scripts/process_eviction_data_12months.R")
   ```

2. **Launch the Shiny app**:
   ```r
   source("scripts/hRisk_app.R")
   ```
   
   Or from terminal:
   ```bash
   Rscript -e "shiny::runApp('scripts/hRisk_app.R', port = 3838, launch.browser = TRUE)"
   ```

3. **Access the application**:
   - Open your web browser
   - Navigate to `http://127.0.0.1:XXXX` (port shown in terminal)

### Application Controls

- **Map Visualization Type**: Choose between bivariate, SVI-only, or eviction-only views
- **Color Palette**: Select different color schemes for individual variable maps
- **Opacity**: Adjust polygon transparency
- **Nonprofit Organizations**: Toggle to show/hide nonprofit locations on the map
- **Layer Controls**: Switch between different map backgrounds

## Data Processing

The application includes a data processing script (`scripts/process_eviction_data_12months.R`) that:

1. Loads raw eviction data from CSV
2. Filters for the past 12 months (July 2024 - June 2025)
3. Aggregates filings by census tract
4. Merges with SVI data and geographic boundaries
5. Creates normalized values for mapping
6. Exports processed data to CSV

## Key Statistics

Based on the 12-month analysis (July 2024 - June 2025):
- **Total Eviction Filings**: 24,954 across all tracts
- **Average Filings per Tract**: 76.1
- **Median Filings per Tract**: 45.0
- **Maximum Filings**: 348 (Tract 75.53)
- **Census Tracts Analyzed**: 328
- **Population Coverage**: 100% of census tracts with 2023 ACS population data
- **Eviction Rate Analysis**: Standardized rates per 1,000 residents for fair comparison across tracts
- **Bivariate Classification**: Color-coded risk assessment (Red = Highest urgency, Gray = Lowest risk)

## Project Structure

```
franklin-county-homelessnessrisk-analysis/
├── README.md                          
├── images/                            
│   └── Screenshot.png              
├── data/                              
│   ├── raw/                        
│   │   ├── Franklin County SVI Data.shp
│   │   └── [other shapefile components]
│   └── processed/                   
│       └── eviction_svi_bivariate_data_12months.csv
├── nonprofits_mapped/                 
│   ├── nonprofit_final_to_geocode.shp
│   └── [other shapefile components]
├── scripts/                         
│   ├── hRisk_app.R                   
│   └── process_eviction_data_12months.R
├── ACSDT5Y2023.B01003-Data.csv      
├── data_dictionary.csv              
└── .gitignore                     
```

## License

This project is open source and available under the MIT License.

## References

U.S. Census Bureau. (2023). American Community Survey 5-Year Estimates (2019-2023). Retrieved from https://www.census.gov/programs-surveys/acs/

Centers for Disease Control and Prevention. (n.d.). Social Vulnerability Index (SVI). Retrieved from https://www.atsdr.cdc.gov/placeandhealth/svi/index.html

Franklin County Court System. (2024-2025). Eviction filing data. Columbus, OH.

U.S. Census Bureau. (2023). TIGER/Line Shapefile, 2023, County: Franklin County, OH - Topological faces polygons with all geocode [Data set]. Retrieved from https://catalog.data.gov/dataset/tiger-line-shapefile-2023-county-franklin-county-oh-topological-faces-polygons-with-all-geocode

## Contact

For questions or contributions, please open an issue on this GitHub repository. 