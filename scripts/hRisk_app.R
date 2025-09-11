# Franklin County Eviction Analysis - Bivariate Map
# Interactive mapping of eviction filings and social vulnerability
# Made by Samyak Shrestha

library(shiny)
library(shinyjs)
library(sf)
library(leaflet)
library(dplyr)
library(readr)
library(RColorBrewer)
library(scales)



bivariate_data <- read_csv("../data/processed/eviction_svi_bivariate_data_12months.csv")
franklin_svi <- st_read("../data/raw/Franklin County SVI Data.shp")
nonprofits <- st_read("../nonprofits_mapped/nonprofit_final_to_geocode.shp") %>%
  st_transform(crs = st_crs(franklin_svi))

# Load population data from Census Bureau
population_data <- read_csv("../ACSDT5Y2023.B01003-Data.csv", skip = 1) %>%
  select(Geography, `Geographic Area Name`, `Estimate!!Total`, `Margin of Error!!Total`) %>%
  rename(
    GEO_ID = Geography,
    census_tract_name = `Geographic Area Name`,
    total_population = `Estimate!!Total`,
    population_margin_error = `Margin of Error!!Total`
  ) %>%
  # Clean GEO_ID to match GEOID format (remove "1400000US" prefix)
  mutate(
    GEOID = gsub("1400000US", "", GEO_ID),
    .before = GEO_ID
  )

#Fix data types
bivariate_data$GEOID <- as.character(bivariate_data$GEOID)
franklin_svi$GEOID <- as.character(franklin_svi$GEOID)

#Merge data
map_data <- franklin_svi %>%
  left_join(bivariate_data, by = "GEOID") %>%
  left_join(population_data, by = "GEOID") %>%
  filter(!is.na(total_filings_12months)) %>%
  mutate(
    NAME = NAME.x,
    ALAND = ALAND.x,
    AWATER = AWATER.x,
    # Calculate eviction rate per 1,000 residents
    eviction_rate_per_1000 = ifelse(
      is.na(total_population) | total_population == 0, 
      NA, 
      round((total_filings_12months / total_population) * 1000, 2)
    )
  ) %>%
  select(-NAME.y, -ALAND.y, -AWATER.y)

cat("Map data loaded successfully!\n")
cat("Number of tracts with data:", nrow(map_data), "\n")
cat("Number of nonprofits loaded:", nrow(nonprofits), "\n")
cat("Population data loaded for", sum(!is.na(map_data$total_population)), "tracts\n")

svi_pal <- colorNumeric( #Color Palettes
  palette = "Reds",
  domain = map_data$SVI_normalized,
  na.color = "transparent"
)

eviction_pal <- colorNumeric(
  palette = "Blues",
  domain = map_data$total_filings_12months,
  na.color = "transparent"
)

#Bivariate color function
create_bivariate_palette <- function(data) {
  colors <- sapply(1:nrow(data), function(i) {
    svi_val <- data$SVI_normalized[i]
    eviction_rate_val <- data$eviction_rate_per_1000[i]
    
    if (is.na(svi_val) || is.na(eviction_rate_val)) return("#f0f0f0")
    
    svi_high <- svi_val > 0.5
    eviction_rate_high <- eviction_rate_val > median(data$eviction_rate_per_1000, na.rm = TRUE)
    
    if (svi_high && eviction_rate_high) {
      return("#e74c3c")  # Red - Highest urgency
    } else if (svi_high && !eviction_rate_high) {
      return("#8e44ad")  # Purple
    } else if (!svi_high && eviction_rate_high) {
      return("#3498db")  # Blue
    } else {
      return("#ecf0f1")  # Gray
    }
  })
  
  return(colors)
}

#User Interface
# User Interface
ui <- fluidPage(
  useShinyjs(),
  tags$head(
    tags$style(HTML("
      body {
        font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
        background: #000000;
        margin: 0;
        padding: 0;
        min-height: 100vh;
      }
      .header {
        background: rgba(255, 255, 255, 0.95);
        backdrop-filter: blur(10px);
        border-bottom: 1px solid rgba(255, 255, 255, 0.2);
        padding: 20px 0;
        margin-bottom: 20px;
        box-shadow: 0 4px 20px rgba(0, 0, 0, 0.1);
      }
      .header h1 {
        color: #2c3e50;
        margin: 0;
        font-size: 2.2em;
        font-weight: 300;
        text-align: center;
        text-shadow: 0 2px 4px rgba(0, 0, 0, 0.1);
      }
      .header p {
        color: #7f8c8d;
        text-align: center;
        margin: 10px 0 0 0;
        font-size: 1.1em;
      }
      .sidebar {
        background: rgba(255, 255, 255, 0.95);
        backdrop-filter: blur(10px);
        border-radius: 15px;
        padding: 25px;
        margin: 20px;
        box-shadow: 0 8px 32px rgba(0, 0, 0, 0.1);
        border: 1px solid rgba(255, 255, 255, 0.2);
      }
      .sidebar h3 {
        color: #2c3e50;
        font-size: 1.4em;
        font-weight: 600;
        margin-bottom: 15px;
        padding-bottom: 8px;
        border-bottom: 2px solid #3498db;
      }
      .sidebar h4 {
        color: #34495e;
        font-size: 1.2em;
        font-weight: 500;
        margin: 20px 0 10px 0;
      }
      .form-group { margin-bottom: 20px; }
      .form-group h5 {
        color: #2c3e50;
        font-weight: 500;
        font-size: 0.95em;
        margin-bottom: 5px;
        display: block;
      }
      .form-control {
        border-radius: 8px;
        border: 2px solid #e0e6ed;
        padding: 10px 12px;
        font-size: 0.9em;
        transition: all 0.3s ease;
      }
      .form-control:focus {
        border-color: #3498db;
        box-shadow: 0 0 0 3px rgba(52, 152, 219, 0.1);
        outline: none;
      }
      .info-box {
        background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
        color: white;
        padding: 15px;
        border-radius: 10px;
        margin: 15px 0;
        box-shadow: 0 4px 15px rgba(0, 0, 0, 0.1);
      }
      .info-box h4 { color: white; margin: 0 0 10px 0; font-size: 1.1em; }
      .info-box p { margin: 5px 0; font-size: 0.9em; opacity: 0.9; }
      .legend-box {
        background: rgba(255, 255, 255, 0.9);
        border-radius: 10px;
        padding: 15px;
        margin: 15px 0;
        box-shadow: 0 4px 15px rgba(0, 0, 0, 0.1);
      }
      .legend-item { display: flex; align-items: center; margin: 8px 0; font-size: 0.9em; color: #2c3e50; }
      .legend-color {
        width: 20px; height: 20px; border-radius: 4px; margin-right: 10px; border: 1px solid #bdc3c7;
      }
      .map-container {
        background: rgba(255, 255, 255, 0.95);
        border-radius: 15px;
        padding: 20px;
        margin: 20px;
        box-shadow: 0 8px 32px rgba(0, 0, 0, 0.1);
        border: 1px solid rgba(255, 255, 255, 0.2);
      }
    "))
  ),  # <-- close tags$head(), keep a comma here

  # Header
  div(
    class = "header",
    h1("Franklin County Homelessness Risk Analysis"),
    p("Interactive Mapping & Statistical Analysis: Eviction Risk + Social Vulnerability Index")
  ),

  # Tab navigation + content
  div(
    style = "margin: 20px;",
    tags$style(HTML("
      .nav-tabs { 
        border-bottom: none; 
        margin-bottom: 0; 
        display: flex;
        justify-content: center;
        padding-left: 0;
        list-style: none;
      }
      .nav-tabs > li { 
        display: inline-block; 
        margin: 0 5px;
      }
      .nav-tabs > li > a {
        background: rgba(255, 255, 255, 0.9);
        border: 2px solid #3498db;
        border-radius: 10px 10px 0 0;
        color: #2c3e50; 
        font-weight: 500;
        padding: 12px 25px; 
        transition: all 0.3s ease;
        display: block;
        text-decoration: none;
      }
      .nav-tabs > li > a:hover { 
        background: #3498db; 
        color: white; 
        border-color: #3498db; 
      }
      .nav-tabs > li.active > a { 
        background: #3498db; 
        color: white; 
        border-color: #3498db; 
      }
      .tab-content {
        background: rgba(255, 255, 255, 0.95);
        border-radius: 0 10px 10px 10px;
        border: 2px solid #3498db; 
        border-top: none;
        padding: 25px; 
        margin: 0 20px 20px 20px;
        box-shadow: 0 8px 32px rgba(0, 0, 0, 0.1);
      }
      
      /* Modal Styles */
      .modal-overlay {
        position: fixed;
        top: 0;
        left: 0;
        width: 100%;
        height: 100%;
        background-color: rgba(0, 0, 0, 0.8);
        z-index: 9999;
        display: flex;
        justify-content: center;
        align-items: center;
      }
      .modal-content {
        background: white;
        border-radius: 15px;
        padding: 30px;
        max-width: 1000px;
        max-height: 80vh;
        overflow-y: auto;
        margin: 20px;
        box-shadow: 0 20px 60px rgba(0, 0, 0, 0.3);
        position: relative;
      }
      .modal-header {
        text-align: center;
        margin-bottom: 25px;
        padding-bottom: 20px;
        border-bottom: 2px solid #3498db;
      }
      .modal-header h2 {
        color: #2c3e50;
        margin: 0;
        font-size: 1.8em;
        font-weight: 600;
      }
      .modal-body {
        color: #34495e;
        line-height: 1.6;
        font-size: 1.1em;
      }
      .modal-body p {
        margin-bottom: 15px;
      }
      .modal-body strong {
        color: #2c3e50;
        font-weight: 600;
      }
      .modal-body a {
        color: #3498db;
        text-decoration: none;
        font-weight: 500;
      }
      .modal-body a:hover {
        text-decoration: underline;
      }
      .modal-footer {
        text-align: center;
        margin-top: 25px;
        padding-top: 20px;
        border-top: 1px solid #ecf0f1;
      }
      .btn-confirm {
        background: linear-gradient(135deg, #3498db, #2980b9);
        color: white;
        border: none;
        padding: 12px 30px;
        border-radius: 8px;
        font-size: 1.1em;
        font-weight: 600;
        cursor: pointer;
        transition: all 0.3s ease;
        box-shadow: 0 4px 15px rgba(52, 152, 219, 0.3);
      }
      .btn-confirm:hover {
        background: linear-gradient(135deg, #2980b9, #1f4e79);
        transform: translateY(-2px);
        box-shadow: 0 6px 20px rgba(52, 152, 219, 0.4);
      }
      .hidden {
        visibility: hidden;
        opacity: 0;
        transition: opacity 0.3s ease;
      }
        .visible {
          visibility: visible;
          opacity: 1;
          transition: opacity 0.3s ease;
        }
        
        /* Map Animation Styles */
        .map-container {
          transition: all 0.5s ease-in-out;
        }
        
        .leaflet-container {
          transition: all 0.5s ease-in-out;
        }
        
        .leaflet-interactive {
          transition: fill 0.5s ease-in-out, stroke 0.5s ease-in-out, opacity 0.5s ease-in-out;
        }
        
        .leaflet-legend {
          transition: all 0.5s ease-in-out;
        }
        
        .leaflet-popup {
          transition: all 0.3s ease-in-out;
        }
        
        .leaflet-marker-icon {
          transition: all 0.3s ease-in-out;
        }
        
        .transitioning {
          transform: scale(0.98);
          opacity: 0.8;
        }
    ")),
    
    # Welcome Modal
    div(id = "welcomeModal", class = "modal-overlay",
        div(class = "modal-content",
            div(class = "modal-header",
                h2("Welcome to Franklin County Homelessness Risk Analysis")
            ),
            div(class = "modal-body",
                p(em("Please note: This is a work in progress project. The analysis and application are being actively developed and refined.")),
                p("Created by Samyak Shrestha | Mentored by Dr. Ayaz Hyder and Special thanks to the Smart Columbus Team!"),
                p("This web application provides interactive maps and statistical analysis to support decision making for homelessness prevention and housing stability efforts. This tool helps identify areas at highest risk of homelessness by analyzing eviction patterns and social vulnerability indicators across Franklin County, Ohio."),
                p(strong("Our aim is to help community organizations, policymakers, and researchers understand the spatial distribution of homelessness risk factors, allowing for targeted interventions to prevent homelessness before it occurs.")),
                p("Please note: If this is your first time using this application, please review the \"Data Dictionary & Sources\" tab to understand the data sources and methodology. This website is provided for informational purposes only. Maps may load slowly during your first use. This application works best when using the Chrome web browser and viewed using a laptop or desktop.")
            ),
            div(class = "modal-footer",
                actionButton("confirmWelcome", "Confirm", class = "btn-confirm")
            )
        )
    ),
    
    # Main Application Content (initially hidden)
    div(id = "mainContent", class = "hidden",
    tabsetPanel(
      tabPanel(
        "Interactive Map",
        fluidRow(
          # Sidebar
          column(
            width = 3,
            div(
              class = "sidebar",
              h3("Map Controls"),

              div(class = "form-group",
                  h5("Map Visualization Type:"),
                  selectInput(
                    "map_type", NULL,
                    choices = c(
                      "Bivariate (SVI + Eviction)" = "Bivariate (SVI + Eviction)",
                      "SVI Only" = "SVI Only",
                      "Eviction Rate Only" = "Eviction Rate Only"
                    ),
                    selected = "Bivariate (SVI + Eviction)"
                  )
              ),

              div(class = "form-group",
                  h5("Color Palette:"),
                  selectInput(
                    "color_palette", NULL,
                    choices = c("Reds" = "Reds", "Blues" = "Blues", "Greens" = "Greens",
                                "Purples" = "Purples", "Oranges" = "Oranges",
                                "Yellow-Orange-Red" = "YlOrRd", "Red-Yellow-Blue" = "RdYlBu"),
                    selected = "Reds"
                  )
              ),

              div(class = "form-group",
                  h5("Polygon Opacity:"),
                  sliderInput("opacity", NULL, min = 0.1, max = 1, value = 0.8, step = 0.1)
              ),

              div(class = "form-group",
                  h5("Nonprofit Organizations:"),
                  checkboxInput("show_nonprofits", "Show Nonprofit Locations", value = FALSE)
              ),


              h4("Bivariate Legend"),
              div(class = "legend-box",
                  div(class = "legend-item",
                      div(class = "legend-color", style = "background-color: #e74c3c;"),
                      span("High SVI + High Eviction Rate (HIGHEST urgency)")
                  ),
                  div(class = "legend-item",
                      div(class = "legend-color", style = "background-color: #8e44ad;"),
                      span("High SVI + Low Eviction Rate (HIGH urgency)")
                  ),
                  div(class = "legend-item",
                      div(class = "legend-color", style = "background-color: #3498db;"),
                      span("Low SVI + High Eviction Rate (MEDIUM urgency)")
                  ),
                  div(class = "legend-item",
                      div(class = "legend-color", style = "background-color: #ecf0f1;"),
                      span("Low SVI + Low Eviction Rate (LOW urgency)")
                  )
              )
            )
          ),

          # Map panel
          column(
            width = 9,
            div(class = "map-container", leafletOutput("map", height = "85vh"))
          )
        ) # end fluidRow
      ), # end tabPanel 1

      tabPanel(
        "Statistical Analysis",
        div(
          style = "padding: 20px;",
          h2("Statistical Analysis", style = "color: #2c3e50; margin-bottom: 30px;"),
          
          # Analysis selection
          div(
            style = "margin-bottom: 20px;",
            selectInput(
              "analysis_type", 
              "Select Analysis Type:",
              choices = c(
                "SVI vs Eviction Rate Correlation" = "correlation",
                "Demographic Analysis (Box Plots)" = "demographic"
              ),
              selected = "correlation"
            )
          ),
          
          # Conditional panels for different analyses
          conditionalPanel(
            condition = "input.analysis_type == 'correlation'",
            h3("SVI vs Eviction Rate Analysis", style = "color: #3498db;"),
            p("This scatterplot shows the relationship between Social Vulnerability Index (SVI) and eviction rates across Franklin County census tracts."),
            br(),
            plotOutput("scatterplot", height = "500px"),
            br(),
            div(
              style = "background: #f8f9fa; padding: 15px; border-radius: 5px; border-left: 4px solid #3498db;",
              h4("Statistical Summary", style = "color: #2c3e50; margin-top: 0;"),
              textOutput("correlation_text"),
              br(),
              textOutput("regression_text")
            ),
            br(),
            div(
              style = "background: #fff3cd; padding: 20px; border-radius: 8px; border-left: 5px solid #ffc107; margin-top: 20px;",
              h4("Hypothesis Testing & Analysis", style = "color: #856404; margin-top: 0;"),
              uiOutput("hypothesis_analysis")
            ),
          ),
          
          conditionalPanel(
            condition = "input.analysis_type == 'demographic'",
            h3("Demographic Analysis", style = "color: #3498db;"),
            p("Box plots showing the distribution of eviction rates across different demographic groups in Franklin County."),
            br(),
            plotOutput("demographic_boxplot", height = "500px"),
            br(),
            div(
              style = "background: #f8f9fa; padding: 15px; border-radius: 5px; border-left: 4px solid #e74c3c;",
              h4("Demographic Summary", style = "color: #2c3e50; margin-top: 0;"),
              textOutput("demographic_summary")
            )
          ),
          
          

        )
      ), # end tabPanel 2

      tabPanel(
        "Data Dictionary & Sources",
        div(
          style = "padding: 20px;",
          h2("Data Dictionary & Sources", style = "color: #2c3e50; margin-bottom: 30px;"),
          h3("Data Sources", style = "color: #3498db; border-bottom: 2px solid #3498db; padding-bottom: 10px;"),
          h4("1. Eviction Data"),
          p("• Source: The Eviction Lab"),
          p("• Processed into a analytic dataset by Samyak Shrestha"),
          p("• Coverage: Franklin County, Ohio monthly eviction filings"),
          p("• Time Period: September 2024 - August 2025 (12 months)"),
          p("• Processing: Aggregated by census tract and converted to rates per 1,000 residents"),
          br(),
          h4("2. Social Vulnerability Index (SVI)"),
          p("• Source: Centers for Disease Control and Prevention (CDC)"),
          p("• Coverage: Franklin County, Ohio"),
          p("• Components: 15 social vulnerability indicators including poverty, unemployment, education, housing, and more"),
          br(),
          h4("3. Population Data"),
          p("• Source: U.S. Census Bureau American Community Survey (ACS)"),
          p("• Coverage: 5-Year Estimates (2019-2023)"),
          p("• Geographic Unit: Census Tract level"),
          p("• File: ACSDT5Y2023.B01003-Data.csv"),
          br(),
          h4("4. Nonprofit Organizations"),
          p("• Source: Human Services Chamber of Franklin County, The Columbus Foundation"),
          p("• Processed and Geocoded into a analytic dataset by Samyak Shrestha and Ayaz Hyder"),
          p("• Coverage: Franklin County, Ohio"),
          p("• Geographic Unit: Point locations"),
          p("• Total Organizations: 1,342"),
          br(),
          h3("Variable Definitions", style = "color: #3498db; border-bottom: 2px solid #3498db; padding-bottom: 10px; margin-top: 40px;"),
          h4("Core Geographic Identifiers"),
          div(style = "background: #f8f9fa; padding: 15px; border-radius: 8px; margin: 15px 0;",
              p("• GEOID: Unique 11-digit Census Tract identifier"),
              p("• NAME: Census Tract name/description"),
              p("• ALAND: Land area in square meters"),
              p("• AWATER: Water area in square meters")
          ),
          h4("Eviction Data Variables"),
          div(style = "background: #f8f9fa; padding: 15px; border-radius: 8px; margin: 15px 0;",
              p("• total_filings_12months: Total eviction filings over 12 months"),
              p("• eviction_rate_per_1000: Eviction rate per 1,000 residents"),
              p("• Calculation: (total_filings_12months / total_population) × 1000"),
              p("• racial_majority: Majority racial/ethnic group for a given tract/zip, based on American Community Survey (ACS) 2015-2019 estimates. ")

          ),
          h4("Social Vulnerability Index (SVI) Variables"),
          div(style = "background: #f8f9fa; padding: 15px; border-radius: 8px; margin: 15px 0;",
              p("• SVI_normalized: Normalized score (0.0 - 1.0)"),
              p("• RPL_THEMES: Overall ranking (percentile 1-100)"),
              p("• EP_POV: Poverty indicator"),
              p("• EP_UNEMP: Unemployment indicator"),
              p("• EP_PCI: Per capita income indicator"),
              p("• EP_NOHSDP: No high school diploma indicator"),
              p("• EP_AGE65: Age 65+ indicator"),
              p("• EP_AGE17: Age 17 and under indicator"),
              p("• EP_DISABL: Disability indicator"),
              p("• EP_SNGPNT: Single parent indicator"),
              p("• EP_MINRTY: Minority status indicator"),
              p("• EP_LIMENG: Limited English indicator"),
              p("• EP_MUNIT: Multi-unit housing indicator"),
              p("• EP_MOBILE: Mobile home indicator"),
              p("• EP_CROWD: Crowding indicator"),
              p("• EP_NOVEH: No vehicle indicator"),
              p("• EP_GROUPQ: Group quarters indicator")
          ),
          h4("Population Demographics"),
          div(style = "background: #f8f9fa; padding: 15px; border-radius: 8px; margin: 15px 0;",
              p("• total_population: Total population count (2023 estimate)"),
              p("• population_margin_error: Margin of error for population estimate")
          ),
          h4("Nonprofit Organization Variables"),
          div(style = "background: #f8f9fa; padding: 15px; border-radius: 8px; margin: 15px 0;",
              p("• name: Organization name"),
              p("• address: Street address"),
              p("• city: City name"),
              p("• state: State abbreviation"),
              p("• zip: ZIP code"),
              p("• geometry: Point coordinates (longitude, latitude)")
          ),
          h3("Bivariate Classification", style = "color: #3498db; border-bottom: 2px solid #3498db; padding-bottom: 10px; margin-top: 40px;"),
          h4("Classification Thresholds"),
          div(style = "background: #f8f9fa; padding: 15px; border-radius: 8px; margin: 15px 0;",
              p("• SVI Classification: High if > 0.5, Low if ≤ 0.5"),
              p("• Eviction Rate Classification: High if > median, Low if ≤ median")
          ),
          h3("Data Processing Notes", style = "color: #3498db; border-bottom: 2px solid #3498db; padding-bottom: 10px; margin-top: 40px;"),
          div(style = "background: #f8f9fa; padding: 15px; border-radius: 8px; margin: 15px 0;",
              p("• Data is merged using GEOID as the primary key"),
              p("• Census tracts with missing eviction data are filtered out"),
              p("• Population data covers 100% of census tracts"),
              p("• SVI data is complete for all 328 census tracts"),
              p("• Eviction rates provide standardized comparison across tracts of different sizes")
          ),
          h3("Quality Control", style = "color: #3498db; border-bottom: 2px solid #3498db; padding-bottom: 10px;"),
          div(style = "background: #f8f9fa; padding: 15px; border-radius: 8px; margin: 15px 0;",
              p("• All 328 census tracts have complete data"),
              p("• Population data loaded for all tracts"),
              p("• Nonprofit data includes 1,342 organizations"),
              p("• Missing values handled with conditional formatting in the UI")
          ),
          h3("References", style = "color: #3498db; border-bottom: 2px solid #3498db; padding-bottom: 10px; margin-top: 40px;"),
          div(style = "background: #f8f9fa; padding: 15px; border-radius: 8px; margin: 15px 0;",
              p("U.S. Census Bureau. (2023). American Community Survey 5-Year Estimates (2019-2023). Retrieved from ",
                a(href = "https://www.census.gov/programs-surveys/acs/", "https://www.census.gov/programs-surveys/acs/")),
              p("Centers for Disease Control and Prevention. (n.d.). Social Vulnerability Index (SVI). Retrieved from ",
                a(href = "https://www.atsdr.cdc.gov/placeandhealth/svi/index.html", "https://www.atsdr.cdc.gov/placeandhealth/svi/index.html")),
              p("Peter Hepburn, Jacob Haas, Renee Louis, Adam Chapnik, Danny Grubbs-Donovan, Olivia Jin, Jasmine Rangel, and Matthew Desmond. Eviction Tracking System: Version 2.0. Princeton: Princeton University, 2020. ",
                a(href = "https://www.evictionlab.org", "www.evictionlab.org")),
              p("U.S. Census Bureau. (2023). TIGER/Line Shapefile, 2023, County: Franklin County, OH - Topological faces polygons with all geocode [Data set]. Retrieved from ",
                a(href = "https://catalog.data.gov/dataset/tiger-line-shapefile-2023-county-franklin-county-oh-topological-faces-polygons-with-all-geocode",
                  "https://catalog.data.gov/dataset/tiger-line-shapefile-2023-county-franklin-county-oh-topological-faces-polygons-with-all-geocode"))
          )
        ) # end inner div of tab 2
      )  # end tabPanel 2
    )  # end tabsetPanel
    ),  # end mainContent div
    
    # JavaScript for modal functionality and map animations
    tags$script(HTML("
      $(document).ready(function() {
        // Show modal on page load
        $('#welcomeModal').show();

        // Handle confirm button click
        $('#confirmWelcome').click(function() {
          $('#welcomeModal').hide();
          $('#mainContent').removeClass('hidden').addClass('visible');
        });
        
        // Map animation functions
        window.animateMapTransition = function() {
          $('.map-container').addClass('transitioning');
          setTimeout(function() {
            $('.map-container').removeClass('transitioning');
          }, 500);
        };
        
        // Add smooth transitions to map controls
        $('.form-group').on('change', 'select, input', function() {
          if ($(this).attr('id') === 'map_type' || $(this).attr('id') === 'color_palette') {
            window.animateMapTransition();
          }
        });
      });
    "))
    
  )  # end outer div containing tabs
)  # <-- FINAL: closes fluidPage


server <- function(input, output, session) {
  
  # Add animated transitions when map type or color palette changes
  observe({
    # Trigger animation when map type changes
    if (!is.null(input$map_type)) {
      shinyjs::runjs("window.animateMapTransition();")
    }
  })
  
  observe({
    # Trigger animation when color palette changes
    if (!is.null(input$color_palette)) {
      shinyjs::runjs("window.animateMapTransition();")
    }
  })
  
  observe({
    # Trigger animation when opacity changes
    if (!is.null(input$opacity)) {
      shinyjs::runjs("window.animateMapTransition();")
    }
  })
  
  # Handle modal confirmation
  observeEvent(input$confirmWelcome, {
    # Hide modal and show main content
    shinyjs::hide("welcomeModal")
    shinyjs::removeClass("mainContent", "hidden")
    shinyjs::addClass("mainContent", "visible")
  })
  
  #Reactive color palette
  reactive_pal <- reactive({
    domain_values <- if(input$map_type == "SVI Only") {
      map_data$SVI_normalized
    } else if(input$map_type == "Eviction Rate Only") {
      map_data$eviction_rate_per_1000
    } else {
      map_data$total_filings_12months
    }
    
    # Remove NA, Inf, and NaN values from domain
    domain_values <- domain_values[!is.na(domain_values) & is.finite(domain_values)]
    
    if(length(domain_values) == 0) {
      # Return a dummy palette if no valid values
      colorNumeric(palette = input$color_palette, domain = c(0, 1), na.color = "transparent")
    } else {
      colorNumeric(palette = input$color_palette, domain = domain_values, na.color = "transparent")
    }
  })
  
  #Create the map
  output$map <- renderLeaflet({
    leaflet(map_data) %>%
      addProviderTiles(providers$CartoDB.Positron, group = "Light") %>%
      addProviderTiles(providers$OpenStreetMap, group = "Street") %>%
      addProviderTiles(providers$Esri.WorldImagery, group = "Satellite") %>%
      
      #Add polygons with data
      addPolygons(
        fillColor = if(input$map_type == "Bivariate (SVI + Eviction)") {
          create_bivariate_palette(map_data)
        } else if (input$map_type == "SVI Only") {
          ~reactive_pal()(SVI_normalized)
        } else {
          ~reactive_pal()(eviction_rate_per_1000)
        },

        weight = 1,
        opacity = 1,
        color = "#2c3e50",
        fillOpacity = input$opacity,
        highlightOptions = highlightOptions(
          weight = 3,
          color = "#3498db",
          fillOpacity = 0.9,
          bringToFront = FALSE
        ),
        popup = ~paste(
          "<div style='font-family: Segoe UI, sans-serif;'>",
          "<h4 style='color: #2c3e50; margin-bottom: 10px;'>Census Tract Information</h4>",
          "<p><strong>Tract:</strong> ", NAME, "</p>",
          "<p><strong>GEOID:</strong> ", GEOID, "</p>",
          "<p><strong>Racial Majority:</strong> ", racial_majority, "</p>",
          "<hr style='border: 1px solid #ecf0f1; margin: 10px 0;'>",
          "<h5 style='color: #e74c3c; margin: 10px 0;'>Eviction Data (Sep 2024 - Aug 2025)</h5>",
          "<p><strong>Total Filings:</strong> ", total_filings_12months, "</p>",
          "<p><strong>Eviction Rate:</strong> ", ifelse(is.na(eviction_rate_per_1000), "N/A", paste(eviction_rate_per_1000, "per 1,000 residents")), "</p>",
          "<p><strong>Total Population (2023):</strong> ", ifelse(is.na(total_population), "N/A", format(total_population, big.mark = ",")), "</p>",
          "<p><strong>Population Margin of Error:</strong> ", ifelse(is.na(population_margin_error), "N/A", format(population_margin_error, big.mark = ",")), "</p>",
          "<hr style='border: 1px solid #ecf0f1; margin: 10px 0;'>",
          "<h5 style='color: #3498db; margin: 10px 0;'>Social Vulnerability</h5>",
          "<p><strong>SVI Value:</strong> ", round(SVI_normalized, 4), "</p>",
          "</div>"
        ),
        label = ~paste("Tract:", NAME, "| Pop:", ifelse(is.na(total_population), "N/A", format(total_population, big.mark = ",")), "| Filings:", total_filings_12months, "| Rate:", ifelse(is.na(eviction_rate_per_1000), "N/A", eviction_rate_per_1000), "| SVI:", round(SVI_normalized, 3)),
        labelOptions = labelOptions(
          style = list("font-weight" = "normal", padding = "3px 8px", "background-color" = "rgba(255,255,255,0.9)", "border-radius" = "4px"),
          textsize = "12px",
          direction = "auto"
        )
      ) %>%
      
      #Add legend based on map type
      addLegend(
        position = "bottomright",
        pal = if(input$map_type == "Bivariate (SVI + Eviction)") {
          colorFactor(
            palette = c("#e74c3c", "#8e44ad", "#3498db", "#ecf0f1"),
            domain = c("High SVI + High Eviction Rate", "High SVI + Low Eviction Rate", 
                      "Low SVI + High Eviction Rate", "Low SVI + Low Eviction Rate")
          )
        } else {
          reactive_pal()
        },
        values = if(input$map_type == "Bivariate (SVI + Eviction)") {
          c("High SVI + High Eviction Rate", "High SVI + Low Eviction Rate", 
            "Low SVI + High Eviction Rate", "Low SVI + Low Eviction Rate")
        } else {
          legend_values <- if(input$map_type == "SVI Only") {
            map_data$SVI_normalized
          } else if(input$map_type == "Eviction Rate Only") {
            map_data$eviction_rate_per_1000
          } else {
            map_data$total_filings_12months
          }
          # Remove NA, Inf, and NaN values
          legend_values[!is.na(legend_values) & is.finite(legend_values)]
        },
        title = if(input$map_type == "Bivariate (SVI + Eviction)") {
          "Bivariate Classification"
        } else if(input$map_type == "SVI Only") {
          "SVI Values"
        } else if(input$map_type == "Eviction Rate Only") {
          "Eviction Rate (per 1,000)"
        } else {
          "Total Filings"
        },
        opacity = 0.9,
        labFormat = if(input$map_type == "Bivariate (SVI + Eviction)") {
          labelFormat()
        } else {
          labelFormat(digits = 4)
        }
      ) %>%

      #Add nonprofit markers with HIGHEST PRIORITY (always on top) - initially hidden
      addCircleMarkers(
        data = nonprofits,
        radius = 4,
        color = "#2c3e50",
        weight = 2,
        opacity = 1.0,
        fillOpacity = 0.8,
        popup = ~paste(
          "<div style='font-family: Segoe UI, sans-serif;'>",
          "<h4 style='color: #2c3e50; margin-bottom: 10px;'>Nonprofit Organization</h4>",
          "<p><strong>Name:</strong> ", Organizati, "</p>",
          "<p><strong>Address:</strong> ", Street_Add, "</p>",
          "<p><strong>City:</strong> ", City, " ", State, " ", ZIP_Code, "</p>",
          "</div>"
        ),
        label = ~Organizati,
        labelOptions = labelOptions(
          style = list("font-weight" = "normal", padding = "3px 8px", "background-color" = "rgba(255,255,255,0.9)", "border-radius" = "4px"),
          textsize = "12px",
          direction = "auto"
        ),
        group = "Nonprofits",
        options = markerOptions(zIndexOffset = 10000)  # Ensure nonprofits are on top with highest priority
      ) %>%
      
      #Add layer controls
      addLayersControl(
        baseGroups = c("Light", "Street", "Satellite"),
        overlayGroups = c("Nonprofits"),
        options = layersControlOptions(collapsed = FALSE)
      ) %>%
      
      #Set view to Franklin County
      setView(lng = -82.9988, lat = 39.9612, zoom = 10) %>%
      
      #Initially hide nonprofit layer (will be shown when checkbox is checked)
      hideGroup("Nonprofits")
  })
  
  #Update map when controls change
  observe({
    leafletProxy("map") %>%
      clearShapes() %>%
      addPolygons(
        data = map_data,
        fillColor = if(input$map_type == "Bivariate (SVI + Eviction)") {
          create_bivariate_palette(map_data)
        } else {
          ~reactive_pal()(if(input$map_type == "SVI Only") SVI_normalized else eviction_rate_per_1000)
        },
        weight = 1,
        opacity = 1,
        color = "#2c3e50",
        fillOpacity = input$opacity,
        highlightOptions = highlightOptions(
          weight = 3,
          color = "#3498db",
          fillOpacity = 0.9,
          bringToFront = FALSE
        ),
        popup = ~paste(
          "<div style='font-family: Segoe UI, sans-serif;'>",
          "<h4 style='color: #2c3e50; margin-bottom: 10px;'>Census Tract Information</h4>",
          "<p><strong>Tract:</strong> ", NAME, "</p>",
          "<p><strong>GEOID:</strong> ", GEOID, "</p>",
          "<p><strong>Racial Majority:</strong> ", racial_majority, "</p>",
          "<hr style='border: 1px solid #ecf0f1; margin: 10px 0;'>",
          "<h5 style='color: #e74c3c; margin: 10px 0;'>Eviction Data (Sep 2024 - Aug 2025)</h5>",
          "<p><strong>Total Filings:</strong> ", total_filings_12months, "</p>",
          "<p><strong>Eviction Rate:</strong> ", ifelse(is.na(eviction_rate_per_1000), "N/A", paste(eviction_rate_per_1000, "per 1,000 residents")), "</p>",
          "<p><strong>Total Population (2023):</strong> ", ifelse(is.na(total_population), "N/A", format(total_population, big.mark = ",")), "</p>",
          "<p><strong>Population Margin of Error:</strong> ", ifelse(is.na(population_margin_error), "N/A", format(population_margin_error, big.mark = ",")), "</p>",
          "<hr style='border: 1px solid #ecf0f1; margin: 10px 0;'>",
          "<h5 style='color: #3498db; margin: 10px 0;'>Social Vulnerability</h5>",
          "<p><strong>SVI Value:</strong> ", round(SVI_normalized, 4), "</p>",
          "</div>"
        ),
        label = ~paste("Tract:", NAME, "| Pop:", ifelse(is.na(total_population), "N/A", format(total_population, big.mark = ",")), "| Filings:", total_filings_12months, "| Rate:", ifelse(is.na(eviction_rate_per_1000), "N/A", eviction_rate_per_1000), "| SVI:", round(SVI_normalized, 3)),
        labelOptions = labelOptions(
          style = list("font-weight" = "normal", padding = "3px 8px", "background-color" = "rgba(255,255,255,0.9)", "border-radius" = "4px"),
          textsize = "12px",
          direction = "auto"
        )
      )
  })
  
  #Observer for nonprofit layer visibility - HIGHEST PRIORITY LAYER
  observe({
    if(input$show_nonprofits) {
      leafletProxy("map") %>%
        showGroup("Nonprofits")
    } else {
      leafletProxy("map") %>%
        hideGroup("Nonprofits")
    }
  })
  
  # Statistical Analysis Outputs
  output$scatterplot <- renderPlot({
    # Filter out NA values for the analysis
    analysis_data <- map_data %>%
      filter(!is.na(SVI_normalized) & !is.na(eviction_rate_per_1000))
    
    # Create scatterplot
    plot(analysis_data$SVI_normalized, analysis_data$eviction_rate_per_1000,
         xlab = "Social Vulnerability Index (SVI)",
         ylab = "Eviction Rate (per 1,000 residents)",
         main = "Relationship Between SVI and Eviction Rates\nFranklin County Census Tracts",
         pch = 19,
         col = alpha("#3498db", 0.6),
         cex = 1.2,
         cex.lab = 1.1,
         cex.main = 1.3,
         cex.axis = 1.0)
    
    # Add regression line
    if(nrow(analysis_data) > 1) {
      lm_model <- lm(eviction_rate_per_1000 ~ SVI_normalized, data = analysis_data)
      abline(lm_model, col = "#e74c3c", lwd = 3)
      
      # Add R-squared text
      r_squared <- summary(lm_model)$r.squared
      text(x = 0.05, y = max(analysis_data$eviction_rate_per_1000, na.rm = TRUE) * 0.9,
           labels = paste("R² =", round(r_squared, 3)),
           cex = 1.2, col = "#e74c3c", font = 2)
    }
    
    # Add grid for better readability
    grid(col = "gray90", lty = "dotted")
  })
  
  output$correlation_text <- renderText({
    # Filter out NA values for the analysis
    analysis_data <- map_data %>%
      filter(!is.na(SVI_normalized) & !is.na(eviction_rate_per_1000))
    
    if(nrow(analysis_data) > 1) {
      correlation <- cor(analysis_data$SVI_normalized, analysis_data$eviction_rate_per_1000)
      
      # Test for significance
      cor_test <- cor.test(analysis_data$SVI_normalized, analysis_data$eviction_rate_per_1000)
      p_value <- cor_test$p.value
      
      significance <- ifelse(p_value < 0.001, "highly significant (p < 0.001)",
                           ifelse(p_value < 0.01, "very significant (p < 0.01)",
                                ifelse(p_value < 0.05, "significant (p < 0.05)",
                                     "not significant (p ≥ 0.05)")))
      
      paste("Correlation Coefficient: r =", round(correlation, 3), 
            "\nThe relationship is", significance,
            "\nSample size:", nrow(analysis_data), "census tracts")
    } else {
      "Insufficient data for correlation analysis"
    }
  })
  
  output$regression_text <- renderText({
    # Filter out NA values for the analysis
    analysis_data <- map_data %>%
      filter(!is.na(SVI_normalized) & !is.na(eviction_rate_per_1000))
    
    if(nrow(analysis_data) > 1) {
      lm_model <- lm(eviction_rate_per_1000 ~ SVI_normalized, data = analysis_data)
      summary_model <- summary(lm_model)
      
      intercept <- coef(lm_model)[1]
      slope <- coef(lm_model)[2]
      r_squared <- summary_model$r.squared
      p_value <- summary_model$coefficients[2, 4]
      
      significance <- ifelse(p_value < 0.001, "highly significant (p < 0.001)",
                           ifelse(p_value < 0.01, "very significant (p < 0.01)",
                                ifelse(p_value < 0.05, "significant (p < 0.05)",
                                     "not significant (p ≥ 0.05)")))
      
      paste("Linear Regression: Eviction Rate =", round(intercept, 2), "+", round(slope, 2), "× SVI",
            "\nR-squared:", round(r_squared, 3), "(" , round(r_squared * 100, 1), "% of variance explained)",
            "\nSlope is", significance,
            "\nInterpretation: For every 0.1-unit increase in SVI, eviction rate changes by", round(slope * 0.1, 2), "per 1,000 residents")
    } else {
      "Insufficient data for regression analysis"
    }
  })
  
  # Hypothesis Testing & Analysis
  output$hypothesis_analysis <- renderUI({
    # Filter out NA values for the analysis
    analysis_data <- map_data %>%
      filter(!is.na(SVI_normalized) & !is.na(eviction_rate_per_1000))
    
    if(nrow(analysis_data) > 10) {
      # Perform correlation test
      cor_test <- cor.test(analysis_data$SVI_normalized, analysis_data$eviction_rate_per_1000)
      correlation <- cor_test$estimate
      p_value <- cor_test$p.value
      
      # Identify high-risk areas (top quartile for both SVI and eviction rates)
      svi_75th <- quantile(analysis_data$SVI_normalized, 0.75, na.rm = TRUE)
      eviction_75th <- quantile(analysis_data$eviction_rate_per_1000, 0.75, na.rm = TRUE)
      
      high_risk_areas <- analysis_data %>%
        filter(SVI_normalized >= svi_75th & eviction_rate_per_1000 >= eviction_75th)
      
      # Calculate statistics
      n_high_risk <- nrow(high_risk_areas)
      total_areas <- nrow(analysis_data)
      high_risk_percentage <- round((n_high_risk / total_areas) * 100, 1)
      
      # Determine pattern strength
      pattern_strength <- ifelse(abs(correlation) >= 0.7, "strong",
                               ifelse(abs(correlation) >= 0.5, "moderate",
                                    ifelse(abs(correlation) >= 0.3, "weak", "very weak")))
      
      # Create hypothesis analysis text
      tags$div(
        tags$h4("HYPOTHESIS:", style = "margin-top: 0; margin-bottom: 10px;"),
        tags$p("Census tracts with higher Social Vulnerability Index (SVI) will have higher eviction rates."),
        
        tags$h4("PATTERN IDENTIFIED:", style = "margin-top: 20px; margin-bottom: 10px;"),
        tags$p(paste0(ifelse(correlation > 0, "Positive", "Negative"), " ", pattern_strength, 
                     " correlation (r = ", round(correlation, 3), ", p = ", round(p_value, 3), ") between SVI and eviction rates.")),
        
        tags$h4("KEY FINDINGS:", style = "margin-top: 20px; margin-bottom: 10px;"),
        tags$ul(
          tags$li(paste0(high_risk_percentage, "% of census tracts (", n_high_risk, " out of ", total_areas, 
                        ") are in the high-risk category (top 25% for both SVI and eviction rates)")),
          tags$li(paste0("High SVI areas show ", round(mean(high_risk_areas$eviction_rate_per_1000, na.rm = TRUE), 1), 
                        " evictions per 1,000 residents on average")),
          tags$li(paste0("Low SVI areas show ", round(mean(analysis_data$eviction_rate_per_1000[analysis_data$SVI_normalized < quantile(analysis_data$SVI_normalized, 0.25, na.rm = TRUE)], na.rm = TRUE), 1), 
                        " evictions per 1,000 residents on average"))
        ),
        
        tags$h4("INTERPRETATION:", style = "margin-top: 20px; margin-bottom: 10px;"),
        tags$p(ifelse(correlation > 0.3, 
                     "Social vulnerability factors (poverty, housing quality, transportation access, etc.) create a compounding effect that increases eviction risk. Areas with multiple social disadvantages face higher housing instability.",
                     "The relationship between social vulnerability and eviction rates is less clear, suggesting other factors may be more influential in eviction patterns.")),
        
        tags$h4("RECOMMENDATIONS:", style = "margin-top: 20px; margin-bottom: 10px;"),
        tags$ul(
          tags$li(paste0("Target high-risk areas (SVI ≥ ", round(svi_75th, 2), ") for intensive eviction prevention programs")),
          tags$li("Implement housing stability services in vulnerable communities before eviction filings occur"),
          tags$li("Focus resources on addressing root causes of social vulnerability (economic opportunity, housing quality, social support)"),
          tags$li("Develop early warning systems to identify at-risk households in high SVI areas"),
          tags$li("Coordinate with nonprofit organizations in high-risk areas for targeted intervention")
        )
      )
    } else {
      "Insufficient data for hypothesis testing analysis"
    }
  })
  
  
  # Demographic Analysis Outputs
  output$demographic_boxplot <- renderPlot({
    # Filter out NA values for the analysis
    analysis_data <- map_data %>%
      filter(!is.na(racial_majority) & !is.na(eviction_rate_per_1000))
    
    # Reorder racial_majority to put Black and White together
    analysis_data$racial_majority <- factor(analysis_data$racial_majority, 
                                           levels = c("Black", "White", "Other"))
    
    # Create boxplot
    boxplot(eviction_rate_per_1000 ~ racial_majority, 
            data = analysis_data,
            main = "Eviction Rates by Racial Demographics\nFranklin County Census Tracts",
            xlab = "Racial Majority by Census Tract (ACS)",
            ylab = "Eviction Rate (per 1,000 residents)",
            col = c("#e74c3c", "#f39c12", "#3498db"),
            cex.lab = 1.1,
            cex.main = 1.3,
            cex.axis = 1.0)
    
    # Add grid for better readability
    grid(col = "gray90", lty = "dotted")
    
    # Add sample sizes as text
    sample_sizes <- table(analysis_data$racial_majority)
    text(x = 1:length(sample_sizes), 
         y = max(analysis_data$eviction_rate_per_1000, na.rm = TRUE) * 0.95,
         labels = paste("n =", sample_sizes),
         cex = 1.0, col = "#2c3e50", font = 2)
  })
  
  output$demographic_summary <- renderText({
    # Filter out NA values for the analysis
    analysis_data <- map_data %>%
      filter(!is.na(racial_majority) & !is.na(eviction_rate_per_1000))
    
    if(nrow(analysis_data) > 1) {
      # Calculate summary statistics by group
      summary_stats <- analysis_data %>%
        group_by(racial_majority) %>%
        summarise(
          mean_rate = round(mean(eviction_rate_per_1000, na.rm = TRUE), 2),
          median_rate = round(median(eviction_rate_per_1000, na.rm = TRUE), 2),
          sd_rate = round(sd(eviction_rate_per_1000, na.rm = TRUE), 2),
          n = n(),
          .groups = 'drop'
        )
      
      # Perform ANOVA test
      anova_result <- aov(eviction_rate_per_1000 ~ racial_majority, data = analysis_data)
      anova_summary <- summary(anova_result)
      p_value <- anova_summary[[1]][["Pr(>F)"]][1]
      
      significance <- ifelse(p_value < 0.001, "highly significant (p < 0.001)",
                           ifelse(p_value < 0.01, "very significant (p < 0.01)",
                                ifelse(p_value < 0.05, "significant (p < 0.05)",
                                     "not significant (p ≥ 0.05)")))
      
      # Create summary text
      summary_text <- "Summary Statistics by Racial Demographics:\n\n"
      for(i in 1:nrow(summary_stats)) {
        summary_text <- paste0(summary_text, 
                              summary_stats$racial_majority[i], ": ",
                              "Mean = ", summary_stats$mean_rate[i], 
                              ", Median = ", summary_stats$median_rate[i],
                              ", SD = ", summary_stats$sd_rate[i],
                              ", n = ", summary_stats$n[i], "\n")
      }
      
      summary_text <- paste0(summary_text, 
                            "\nANOVA Test: Differences between groups are ", significance,
                            "\nTotal sample size: ", nrow(analysis_data), " census tracts")
      
      return(summary_text)
    } else {
      "Insufficient data for demographic analysis"
    }
  })
  
  

  
}

#Run app
shinyApp(ui = ui, server = server) 