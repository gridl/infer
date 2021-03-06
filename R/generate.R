#' Generate resamples, permutations, or simulations based on
#' `specify` and (if needed) `hypothesize` inputs
#' @param x a data frame that can be coerced into a \code{\link[dplyr]{tbl_df}}
#' @param reps the number of resamples to generate
#' @param type currently either \code{bootstrap}, \code{permute}, 
#' or \code{simulate}
#' @param ... currently ignored
#' @return A tibble containing \code{rep} generated datasets, indicated by the
#' \code{replicate} column.
#' @importFrom dplyr group_by
#' @export
#' @examples
#' # Permutation test for two binary variables
#'   mtcars %>%
#'     dplyr::mutate(am = factor(am), vs = factor(vs)) %>%
#'     specify(am ~ vs, success = "1") %>%
#'     hypothesize(null = "independence") %>%
#'     generate(reps = 100, type = "permute")

generate <- function(x, reps = 1, type = attr(x, "type"), ...) {

  auto_type <- attr(x, "type")
  
  if(!is.null(auto_type)){
    if(auto_type != type)
      stop_glue(
        "You have specified `type = \"{type}\"`, but `type` is expected to be ",
        "`\"{auto_type}\"`. Please try again with appropriate `type` value."
      )
    else
      type <- auto_type
  }
  
  attr(x, "generate") <- TRUE
  
  if (type == "permute" &&
      any(is.null(attr(x, "response")), is.null(attr(x, "explanatory")))) {
    stop_glue("Please `specify()` an explanatory and a response variable ",
              "when permuting.")
  }
## Can't get to these anymore with tests
#  if (type == "simulate" &&
#      attr(x, "null") != "point" &&
#      !(length(grep("p.", names(attr(x, "params")))) >= 1)) {
#    stop_glue("Simulation requires a `point` null hypothesis on proportions.")
#  }
#  if (type == "bootstrap" &&
#        !(attr(attr(x, "params"), "names") %in% c("mu", "med", "sigma")) &&
#        !is.null(attr(x, "null"))
#      ) {
#    stop_glue("Bootstrapping is inappropriate in this setting. ",
#              "Consider using `type = permute` or `type = simulate`.")
#  }

  if (type == "bootstrap") {
    return(bootstrap(x, reps, ...))
  }
  else if (type == "permute") {
    return(permute(x, reps, ...))
  }
  else if (type == "simulate") {
    return(simulate(x, reps, ...))
  }
#  else if (!(type %in% c("bootstrap", "permute", "simulate")))
#    stop_glue("Choose one of the available options for `type`: ",
#              '`"bootstrap"`, `"permute"`, or `"simulate"`')
}

bootstrap <- function(x, reps = 1, ...) {
  # Check if hypothesis test chosen
  if(!is.null(attr(x, "null"))){
    # If so, shift the variable chosen to have a mean corresponding
    # to that specified in `hypothesize`
    if(attr(attr(x, "params"), "names") == "mu"){
      
      col <- as.character(attr(x, "response"))
#      if(attr(x, "theory_type") != "One sample t"){
        x[[col]] <- x[[col]] - mean(x[[col]], na.rm = TRUE) + attr(x, "params")
#      }
    
      # Standardize after centering above
      #####
      # Determining whether or not to implement this t transformation
      #####
#      else {
#        std_error <- stats::sd(x[[col]], na.rm = TRUE) / 
#                        sqrt(length(x[[col]]))
#        x[[col]] <- ( x[[col]] - mean(x[[col]], na.rm = TRUE) ) / std_error
#      }
    }

    # Similarly for median
    else if(attr(attr(x, "params"), "names") == "med"){
      col <- as.character(attr(x, "response"))
      x[[col]] <- x[[col]] -
        stats::median(x[[col]], na.rm = TRUE) + attr(x, "params")
    }

    # Implement confidence interval for bootstrapped proportions?
    # Implement z transformation?

    # Similarly for sd
    ## Temporarily removed since this implementation does not scale correctly
    # else if(attr(attr(x, "params"), "names") == "sigma"){
    #   col <- as.character(attr(x, "response"))
    #   x[[col]] <- x[[col]] -
    #     stats::sd(x[[col]], na.rm = TRUE) + attr(x, "params")
    # }
  }

  # Set variables for use in calculate()
  result <- rep_sample_n(x, size = nrow(x), replace = TRUE, reps = reps)
  result <- set_attributes(to = result, from = x)
  
  class(result) <- append("infer", class(result))
  
  return(result)
}

#' @importFrom dplyr bind_rows group_by

permute <- function(x, reps = 1, ...) {
  df_out <- replicate(reps, permute_once(x), simplify = FALSE) %>%
    dplyr::bind_rows() %>%
    dplyr::mutate(replicate = rep(1:reps, each = nrow(x))) %>%
    dplyr::group_by(replicate)
  
  df_out <- set_attributes(to = df_out, from = x)
  
  class(df_out) <- append("infer", class(df_out))
  
  return(df_out)
}

permute_once <- function(x, ...) {
  dots <- list(...)

  if (attr(x, "null") == "independence") {
    y <- pull(x, !! attr(x, "response"))

    y_prime <- sample(y, size = length(y), replace = FALSE)
    x[as.character(attr(x, "response"))] <- y_prime
    return(x)
  }

}

#' @importFrom dplyr pull
#' @importFrom tibble tibble
#' @importFrom rlang :=

simulate <- function(x, reps = 1, ...) {
  fct_levels <- as.character(unique(dplyr::pull(x, !! attr(x, "response"))))

  col_simmed <- unlist(replicate(reps, sample(fct_levels,
                                              size = nrow(x),
                                              replace = TRUE,
                                              prob = format_params(x)),
                                 simplify = FALSE))

  rep_tbl <- tibble(!! attr(x, "response") := as.factor(col_simmed),
                   replicate = as.factor(rep(1:reps, rep(nrow(x), reps))))

  rep_tbl <- set_attributes(to = rep_tbl, from = x)
  
  class(rep_tbl) <- append("infer", class(rep_tbl))

  return(dplyr::group_by(rep_tbl, replicate))
}


