get_ors_response <- function(
        origin_coords, 
        dest_coords, 
        arrival, 
        url = "http://localhost:8080/ors/v2/directions/driving-car"
) {
    headers = c(
        'Content-Type' = 'application/json'
    )
    
    body <- list(
        coordinates = list(origin_coords, dest_coords),
        arrival = arrival,
        instructions = FALSE
    ) |> jsonlite::toJSON(auto_unbox = TRUE)

    res <- POST(url = url, body = body, add_headers(headers))
}

get_route <- function(row) {

    origin_coord <- row[1,1] |> st_coordinates() |> as.numeric()
    dest_coord <- row[1,2] |> st_coordinates() |> as.numeric()
    arrival <- row[1,3]
    
    res <- get_ors_response(
        origin_coords = origin_coord,
        dest_coords = dest_coord,
        arrival = arrival
    )
    
    
    if (res$status_code != 200) {
        
        result <- data.frame(status=res$status_code)
        
    } else {
        json_resp <- res$content |> rawToChar() |> jsonlite::fromJSON()
        result <- json_resp$routes |> as.data.frame()
        result <- result |> mutate(geom = gp2sf(geometry)) |>
            st_sf(crs = "EPSG:4326")
        result$status <- res$status_code
        result$distance <- result$summary$distance
        result$duration <- result$summary$duration
        result <- result |> select(-c(summary))
    }
    result
}

get_routes <- function(
        origin_centroids, 
        dest_centroids, 
        origin_ids, 
        dest_ids, 
        arrivals
) {
    
    stopifnot(length(origin_centroids) == length(origin_ids))
    stopifnot(length(dest_centroids) == length(dest_ids))

    grid <- expand.grid(origin_centroids, dest_centroids, arrivals)
    ids <- expand.grid(origin_id = origin_ids, dest_id = dest_ids, arrival = arrivals)
    
    split(grid, seq(nrow(grid))) |>
        map(get_route) |>
        reduce(bind_rows) |>
        cbind(ids)
}
