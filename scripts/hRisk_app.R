# Franklin County Eviction Analysis - Bivariate Map
# Interactive mapping of eviction filings and social vulnerability
# Made by Samyak Shrestha

library(shiny)
library(sf)
library(leaflet)
library(dplyr)
library(readr)
library(RColorBrewer)

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
    eviction_val <- data$total_filings_12months[i]
    
    if (is.na(svi_val) || is.na(eviction_val)) return("#f0f0f0")
    
    svi_high <- svi_val > 0.5
    eviction_high <- eviction_val > median(data$total_filings_12months, na.rm = TRUE)
    
    if (svi_high && eviction_high) {
      return("#8e44ad")  # Purple
    } else if (svi_high && !eviction_high) {
      return("#e74c3c")  # Red
    } else if (!svi_high && eviction_high) {
      return("#3498db")  # Blue
    } else {
      return("#ecf0f1")  # Gray
    }
  })
  
  return(colors)
}

#User Interface
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
      
      /* Header styling */
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
      
      /* Sidebar styling */
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
      
      /* Control styling */
      .form-group {
        margin-bottom: 20px;
      }
      
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
      
      /* Info boxes */
      .info-box {
        background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
        color: white;
        padding: 15px;
        border-radius: 10px;
        margin: 15px 0;
        box-shadow: 0 4px 15px rgba(0, 0, 0, 0.1);
      }
      
      .info-box h4 {
        color: white;
        margin: 0 0 10px 0;
        font-size: 1.1em;
      }
      
      .info-box p {
        margin: 5px 0;
        font-size: 0.9em;
        opacity: 0.9;
      }
      
      /* Statistics box */
      .stats-box {
        background: rgba(52, 152, 219, 0.1);
        border: 2px solid #3498db;
        border-radius: 10px;
        padding: 15px;
        margin: 15px 0;
        font-family: 'Courier New', monospace;
        font-size: 0.85em;
        color: #2c3e50;
      }
      
      /* Legend box */
      .legend-box {
        background: rgba(255, 255, 255, 0.9);
        border-radius: 10px;
        padding: 15px;
        margin: 15px 0;
        box-shadow: 0 4px 15px rgba(0, 0, 0, 0.1);
      }
      
      .legend-item {
        display: flex;
        align-items: center;
        margin: 8px 0;
        font-size: 0.9em;
        color: #2c3e50;
      }
      
      .legend-color {
        width: 20px;
        height: 20px;
        border-radius: 4px;
        margin-right: 10px;
        border: 1px solid #bdc3c7;
      }
      
      /* Map container */
      .map-container {
        background: rgba(255, 255, 255, 0.95);
        border-radius: 15px;
        padding: 20px;
        margin: 20px;
        box-shadow: 0 8px 32px rgba(0, 0, 0, 0.1);
        border: 1px solid rgba(255, 255, 255, 0.2);
      }
    "))
  ),
  
  #Header
  div(class = "header",
    h1("Franklin County Eviction & Social Vulnerability Analysis"),
    p("Interactive Bivariate Map: 12-Month Eviction Filings (July 2024 - June 2025) + Social Vulnerability Index")
  ),
  
  #Main layout
  fluidRow(
    #Sidebar panel
    column(width = 3,
      div(class = "sidebar",
        h3("Map Controls"),
        
        #Map type selection
        div(class = "form-group",
          h5("Map Visualization Type:"),
          selectInput("map_type", 
                     NULL,
                     choices = c("Bivariate (SVI + Eviction)" = "Bivariate (SVI + Eviction)", 
                                "SVI Only" = "SVI Only", 
                                "Eviction Filings Only" = "Eviction Filings Only"),
                     selected = "Bivariate (SVI + Eviction)")
        ),
        
        #Color palette for individual maps
        div(class = "form-group",
          h5("Color Palette:"),
          selectInput("color_palette", 
                     NULL,
                     choices = c("Reds" = "Reds", "Blues" = "Blues", "Greens" = "Greens", 
                                "Purples" = "Purples", "Oranges" = "Oranges", 
                                "Yellow-Orange-Red" = "YlOrRd", "Red-Yellow-Blue" = "RdYlBu"),
                     selected = "Reds")
        ),
        
        #Opacity control
        div(class = "form-group",
          h5("Polygon Opacity:"),
          sliderInput("opacity", 
                     NULL,
                     min = 0.1, 
                     max = 1, 
                     value = 0.8, 
                     step = 0.1)
        ),
        
        #Nonprofit layer control
        div(class = "form-group",
          h5("Nonprofit Organizations:"),
          checkboxInput("show_nonprofits", 
                       "Show Nonprofit Locations", 
                       value = FALSE)
        ),
        
        #Information about the data
        h4("Data Information"),
        div(class = "info-box",
          h4("Time Period"),
          p("Eviction data covers July 2024 - June 2025"),
          p("(12 months of recent eviction filings)"),
          p("SVI data represents social vulnerability index")
        ),
        
        #Statistics
        h4("Statistics"),
        div(class = "stats-box",
          verbatimTextOutput("stats")
        ),
        
        #Legend 
        h4("Bivariate Legend"),
        div(class = "legend-box",
          div(class = "legend-item",
            div(class = "legend-color", style = "background-color: #8e44ad;"),
            span("High SVI + High Eviction")
          ),
          div(class = "legend-item",
            div(class = "legend-color", style = "background-color: #e74c3c;"),
            span("High SVI + Low Eviction")
          ),
          div(class = "legend-item",
            div(class = "legend-color", style = "background-color: #3498db;"),
            span("Low SVI + High Eviction")
          ),
          div(class = "legend-item",
            div(class = "legend-color", style = "background-color: #ecf0f1;"),
            span("Low SVI + Low Eviction")
          )
        )
      )
    ),
    
    #Main map panel
    column(width = 9,
      div(class = "map-container",
        leafletOutput("map", height = "85vh")
      )
    )
  )
)

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
      ) %>%
      
      #Add legend based on map type
      addLegend(
        position = "bottomright",
        pal = if(input$map_type == "Bivariate (SVI + Eviction)") {
          colorFactor(
            palette = c("#8e44ad", "#e74c3c", "#3498db", "#ecf0f1"),
            domain = c("High SVI + High Eviction", "High SVI + Low Eviction", 
                      "Low SVI + High Eviction", "Low SVI + Low Eviction")
          )
        } else {
          reactive_pal()
        },
        values = if(input$map_type == "Bivariate (SVI + Eviction)") {
          c("High SVI + High Eviction", "High SVI + Low Eviction", 
            "Low SVI + High Eviction", "Low SVI + Low Eviction")
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
  
  #Statistics output
  output$stats <- renderPrint({
    cat("12-Month Eviction Statistics\n")
    cat("===============================\n\n")
    cat("Time Period: July 2024 - June 2025\n")
    cat("Total Census Tracts: ", nrow(map_data), "\n")
    cat("Total Eviction Filings: ", sum(map_data$total_filings_12months, na.rm = TRUE), "\n")
    cat("Total Nonprofits: ", nrow(nonprofits), "\n\n")
    cat("Population Statistics (2023):\n")
    cat("   • Total Population: ", format(sum(map_data$total_population, na.rm = TRUE), big.mark = ","), "\n")
    cat("   • Average per Tract: ", format(round(mean(map_data$total_population, na.rm = TRUE), 0), big.mark = ","), "\n")
    cat("   • Median per Tract:  ", format(round(median(map_data$total_population, na.rm = TRUE), 0), big.mark = ","), "\n")
    cat("   • Maximum: ", format(max(map_data$total_population, na.rm = TRUE), big.mark = ","), "\n")
    cat("   • Minimum: ", format(min(map_data$total_population, na.rm = TRUE), big.mark = ","), "\n\n")
    cat("Eviction Rate Statistics (per 1,000 residents):\n")
    cat("   • Average Rate: ", round(mean(map_data$eviction_rate_per_1000, na.rm = TRUE), 2), "\n")
    cat("   • Median Rate:  ", round(median(map_data$eviction_rate_per_1000, na.rm = TRUE), 2), "\n")
    cat("   • Maximum Rate: ", round(max(map_data$eviction_rate_per_1000, na.rm = TRUE), 2), "\n")
    cat("   • Minimum Rate: ", round(min(map_data$eviction_rate_per_1000, na.rm = TRUE), 2), "\n\n")
    cat("Filing Statistics:\n")
    cat("   • Average: ", round(mean(map_data$total_filings_12months, na.rm = TRUE), 1), "\n")
    cat("   • Median:  ", round(median(map_data$total_filings_12months, na.rm = TRUE), 1), "\n")
    cat("   • Maximum: ", round(max(map_data$total_filings_12months, na.rm = TRUE), 1), "\n")
    cat("   • Minimum: ", round(min(map_data$total_filings_12months, na.rm = TRUE), 1), "\n\n")
    cat("SVI Statistics:\n")
    cat("   • Average SVI: ", round(mean(map_data$SVI_normalized, na.rm = TRUE), 4), "\n")
    cat("   • Max SVI:     ", round(max(map_data$SVI_normalized, na.rm = TRUE), 4), "\n")
    cat("   • Min SVI:     ", round(min(map_data$SVI_normalized, na.rm = TRUE), 4), "\n")
  })
}

#Run app
shinyApp(ui = ui, server = server) 