# Franklin County Eviction Analysis - Bivariate Map
# Interactive mapping of eviction filings and social vulnerability
# Made by Samyak Shrestha

library(shiny)
library(sf)
library(leaflet)
library(dplyr)
library(readr)
library(RColorBrewer)

bivariate_data <- read_csv("data/processed/eviction_svi_bivariate_data_12months.csv")
franklin_svi <- st_read("data/raw/Franklin County SVI Data.shp")
nonprofits <- st_read("nonprofits_mapped/nonprofit_final_to_geocode.shp") %>%
  st_transform(crs = st_crs(franklin_svi))

# Load population data from Census Bureau
population_data <- read_csv("ACSDT5Y2023.B01003-Data.csv", skip = 1) %>%
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
    eviction_rate_per_1000 = round((total_filings_12months / total_population) * 1000, 2)
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
    h1("Franklin County Eviction & Social Vulnerability Analysis"),
    p("Interactive Bivariate Map: Eviction Rate + Social Vulnerability Index")
  ),

  # Tab navigation + content
  div(
    style = "text-align: center; margin: 20px;",
    tags$style(HTML("
      .nav-tabs { border-bottom: none; margin-bottom: 0; }
      .nav-tabs > li > a {
        background: rgba(255, 255, 255, 0.9);
        border: 2px solid #3498db;
        border-radius: 10px 10px 0 0;
        margin-right: 5px; color: #2c3e50; font-weight: 500;
        padding: 12px 25px; transition: all 0.3s ease;
      }
      .nav-tabs > li > a:hover { background: #3498db; color: white; border-color: #3498db; }
      .nav-tabs > li.active > a { background: #3498db; color: white; border-color: #3498db; }
      .tab-content {
        background: rgba(255, 255, 255, 0.95);
        border-radius: 0 10px 10px 10px;
        border: 2px solid #3498db; border-top: none;
        padding: 25px; margin: 0 20px 20px 20px;
        box-shadow: 0 8px 32px rgba(0, 0, 0, 0.1);
      }
    ")),
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
                      "Eviction Filings Only" = "Eviction Filings Only"
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

              h4("Data Information"),
              div(class = "info-box",
                  h4("Time Period"),
                  p("Eviction data covers July 2024 - June 2025"),
                  p("(12 months of recent eviction filings)"),
                  p("SVI data represents social vulnerability index")
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
        "Data Dictionary & Sources",
        div(
          style = "padding: 20px;",
          h2("Data Dictionary & Sources", style = "color: #2c3e50; margin-bottom: 30px;"),
          h3("Data Sources", style = "color: #3498db; border-bottom: 2px solid #3498db; padding-bottom: 10px;"),
          h4("1. Eviction Data"),
          p("• Source: Franklin County Court System"),
          p("• Coverage: Franklin County, Ohio monthly eviction filings"),
          p("• Time Period: July 2024 - June 2025 (12 months)"),
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
          p("• Source: Geocoded nonprofit locations"),
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
              p("• Calculation: (total_filings_12months / total_population) × 1000")
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
              p("• population_margin_error: Margin of error for population estimate"),
              p("• racial_majority: Racial/ethnic group with highest population")
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
          )
        ) # end inner div of tab 2
      )  # end tabPanel 2
    )  # end tabsetPanel
  )  # end outer div containing tabs
)  # <-- FINAL: closes fluidPage


server <- function(input, output, session) {
  
  #Reactive color palette
  reactive_pal <- reactive({
    colorNumeric(
      palette = input$color_palette,
      domain = if(input$map_type == "SVI Only") {
        map_data$SVI_normalized
      } else {
        map_data$total_filings_12months
      },
      na.color = "transparent"
    )
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
          ~reactive_pal()(total_filings_12months)
        },

        weight = 1,
        opacity = 1,
        color = "#2c3e50",
        fillOpacity = input$opacity,
        highlightOptions = highlightOptions(
          weight = 3,
          color = "#3498db",
          fillOpacity = 0.9,
          bringToFront = TRUE
        ),
        popup = ~paste(
          "<div style='font-family: Segoe UI, sans-serif;'>",
          "<h4 style='color: #2c3e50; margin-bottom: 10px;'>Census Tract Information</h4>",
          "<p><strong>Tract:</strong> ", NAME, "</p>",
          "<p><strong>GEOID:</strong> ", GEOID, "</p>",
          "<p><strong>Racial Majority:</strong> ", racial_majority, "</p>",
          "<hr style='border: 1px solid #ecf0f1; margin: 10px 0;'>",
          "<h5 style='color: #e74c3c; margin: 10px 0;'>Eviction Data (Jul 2024 - Jun 2025)</h5>",
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
          if(input$map_type == "SVI Only") map_data$SVI_normalized else map_data$total_filings_12months
        },
        title = if(input$map_type == "Bivariate (SVI + Eviction)") {
          "Bivariate Classification"
        } else if(input$map_type == "SVI Only") {
          "SVI Values"
        } else {
          "Eviction Filings"
        },
        opacity = 0.9,
        labFormat = if(input$map_type == "Bivariate (SVI + Eviction)") {
          labelFormat()
        } else {
          labelFormat(digits = 4)
        }
      ) %>%

      #Add layer controls
      addLayersControl(
        baseGroups = c("Light", "Street", "Satellite"),
        options = layersControlOptions(collapsed = FALSE)
      ) %>%
      
      #Set view to Franklin County
      setView(lng = -82.9988, lat = 39.9612, zoom = 10)
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
          ~reactive_pal()(if(input$map_type == "SVI Only") SVI_normalized else total_filings_12months)
        },
        weight = 1,
        opacity = 1,
        color = "#2c3e50",
        fillOpacity = input$opacity,
        highlightOptions = highlightOptions(
          weight = 3,
          color = "#3498db",
          fillOpacity = 0.9,
          bringToFront = TRUE
        ),
        popup = ~paste(
          "<div style='font-family: Segoe UI, sans-serif;'>",
          "<h4 style='color: #2c3e50; margin-bottom: 10px;'>Census Tract Information</h4>",
          "<p><strong>Tract:</strong> ", NAME, "</p>",
          "<p><strong>GEOID:</strong> ", GEOID, "</p>",
          "<p><strong>Racial Majority:</strong> ", racial_majority, "</p>",
          "<hr style='border: 1px solid #ecf0f1; margin: 10px 0;'>",
          "<h5 style='color: #e74c3c; margin: 10px 0;'>Eviction Data (Jul 2024 - Jun 2025)</h5>",
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
  
  #Observer for nonprofit layer visibility
  observe({
    leafletProxy("map") %>%
      clearGroup("Nonprofits")
    
    if(input$show_nonprofits) {
      leafletProxy("map") %>%
        addCircleMarkers(
          data = nonprofits,
          radius = 4,
          color = "#2c3e50",
          weight = 2,
          opacity = 0.8,
          fillOpacity = 0.6,
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
          group = "Nonprofits"
        ) %>%
        addLayersControl(
          baseGroups = c("Light", "Street", "Satellite"),
          overlayGroups = c("Nonprofits"),
          options = layersControlOptions(collapsed = FALSE)
        )
    } else {
      leafletProxy("map") %>%
        addLayersControl(
          baseGroups = c("Light", "Street", "Satellite"),
          options = layersControlOptions(collapsed = FALSE)
        )
    }
  })
  
}

#Run app
shinyApp(ui = ui, server = server) 