# H2O Machine Learning Tutorial: Grid Search and Model Selection
# Prepared for H2O Open Chicago 2016: http://open.h2o.ai/chicago.html
# First step is to download & install the h2o R library
# The latest version is always here: http://www.h2o.ai/download/h2o/r

# Load the H2O library and start up the H2O cluter locally on your machine
library(h2o)
h2o.init(nthreads = -1,        # Number of threads -1 means use all cores on your machine
         max_mem_size = "8G")  # Max mem size is the maximum memory to allocate to H2O


# Import data -------------------------------------------------------------------------------------
# Respons is 1 (bad load) or 0 (okay loan)
loan_csv <- "https://raw.githubusercontent.com/h2oai/app-consumer-loan/master/data/loan.csv"
data <- h2o.importFile(loan_csv)
dim(data)

# In a binary classification model, response needs to be a factor
data$bad_loan <- as.factor(data$bad_loan) 
h2o.levels(data$bad_loan)  

# Partition the data into training (70%), validation (15%) and test (15%) sets
splits <- h2o.splitFrame(data = data, 
                         ratios = c(0.7, 0.15),
                         seed = 1)  
train <- splits[[1]]
valid <- splits[[2]]
test <- splits[[3]]

# Take a look at the size of each partition
# Notice that h2o.splitFrame uses approximate splitting not exact splitting (for efficiency)
# so these are not exactly 70%, 15% and 15% of the total rows
nrow(train) 
nrow(valid) 
nrow(test)  

# Identify response and predictor variables
y <- "bad_loan"
# Remove the interest rate column because it's correlated with the outcome
x <- setdiff(names(data), c(y, "int_rate")) 


# *** GBM *** ----


# Cartesian Grid Search ---------------------------------------------------------------------------
# By default, h2o.grid will train a Cartesian grid search - all models in the specified grid 

# GBM hyperparamters
gbm_params1 <- list(learn_rate = c(0.01, 0.1),
                    max_depth = c(3, 5, 9),
                    sample_rate = c(0.8, 1.0),
                    col_sample_rate = c(0.2, 0.5, 1.0))

# Train and validate a grid of GBMs
gbm_grid1 <- h2o.grid("gbm", x = x, y = y,
                      grid_id = "gbm_grid1",
                      training_frame = train,
                      validation_frame = valid,
                      ntrees = 100,
                      seed = 1,
                      hyper_params = gbm_params1)

# Get the grid results, sorted by AUC
gbm_gridperf1 <- h2o.getGrid(grid_id = "gbm_grid1", 
                             sort_by = "auc", 
                             decreasing = TRUE)
print(gbm_gridperf1)


# Random Grid Search ------------------------------------------------------------------------------
# This is set to run fairly quickly, increase max_runtime_secs 
# or max_models to cover more of the hyperparameter space.
# Also, you can expand the hyperparameter space of each of the 
# algorithms by modifying the hyper param code below.

# GBM hyperparamters
gbm_params2 <- list(learn_rate = seq(0.01, 0.1, 0.01),
                    max_depth = seq(2, 10, 1),
                    sample_rate = seq(0.5, 1.0, 0.1),
                    col_sample_rate = seq(0.1, 1.0, 0.1))

search_criteria2 <- list(strategy = "RandomDiscrete", 
                         max_models = 36)

# Train and validate a grid of GBMs
gbm_grid2 <- h2o.grid("gbm", x = x, y = y,
                      grid_id = "gbm_grid2",
                      training_frame = train,
                      validation_frame = valid,
                      ntrees = 100,
                      seed = 1,
                      hyper_params = gbm_params2,
                      search_criteria = search_criteria2)

gbm_gridperf2 <- h2o.getGrid(grid_id = "gbm_grid2", 
                             sort_by = "auc", 
                             decreasing = TRUE)
print(gbm_gridperf2)

# Adding models to existing grid ------------------------------------------------------------------

# Looks like learn_rate = 0.1 does well here, which was the biggest 
# learn_rate in our previous search, so maybe we want to 
# add some models to our grid search with a higher learn_rate.
# We can add models to the same grid, by re-using the same model_id.
# Let's add as many new models as we can train in 60 seconds by setting
# max_runtime_secs = 60 in search_criteria.

gbm_params <- list(learn_rate = seq(0.1, 0.3, 0.01),     # updated
                   max_depth = seq(2, 10, 1),
                   sample_rate = seq(0.9, 1.0, 0.05),    # updated
                   col_sample_rate = seq(0.1, 1.0, 0.1))

search_criteria <- list(strategy = "RandomDiscrete", 
                        max_runtime_secs = 60)           # updated

gbm_grid <- h2o.grid("gbm", x = x, y = y,
                     grid_id = "gbm_grid2",
                     training_frame = train,
                     validation_frame = valid,
                     ntrees = 100,
                     seed = 1,
                     hyper_params = gbm_params,
                     search_criteria = search_criteria2)

gbm_gridperf <- h2o.getGrid(grid_id = "gbm_grid2", 
                            sort_by = "auc", 
                            decreasing = TRUE)
print(gbm_gridperf)


# Choosing best model -----------------------------------------------------------------------------
# Grab the model_id for the top GBM model, chosen by validation AUC
best_gbm_model_id <- gbm_gridperf@model_ids[[1]]
best_gbm <- h2o.getModel(best_gbm_model_id)


# Evaluate on test set ----------------------------------------------------------------------------
# Now let's evaluate the model performance on a test set
# so we get an honest estimate of top model performance
best_gbm_perf <- h2o.performance(model = best_gbm, 
                                 newdata = test)
h2o.auc(best_gbm_perf)  

# As we can see, this is slighly less than the AUC on the validation set
# of the top model, but this is a more honest estimate of performance.  
# The validation set was used to select the best model, but should not 
# be used to also evaluate the best model's performance.


# *** DeepLearning *** ----


# Deeplearning hyperparamters
activation_opt <- c("Rectifier", "RectifierWithDropout", "Maxout", "MaxoutWithDropout")
l1_opt <- c(0, 0.00001, 0.0001, 0.001, 0.01, 0.1)
l2_opt <- c(0, 0.00001, 0.0001, 0.001, 0.01, 0.1)
hyper_params <- list(activation = activation_opt,
                     l1 = l1_opt,
                     l2 = l2_opt)
search_criteria <- list(strategy = "RandomDiscrete", 
                        max_runtime_secs = 120)


dl_grid <- h2o.grid("deeplearning", x = x, y = y,
                    grid_id = "dl_grid",
                    training_frame = train,
                    validation_frame = valid,
                    seed = 1,
                    hidden = c(10,10),
                    hyper_params = hyper_params,
                    search_criteria = search_criteria)

dl_gridperf <- h2o.getGrid(grid_id = "dl_grid", 
                           sort_by = "auc", 
                           decreasing = TRUE)
print(dl_gridperf)

# Note that that these results are not reproducible since we are not using a single core H2O cluster
# H2O's DL requires a single core to be used in order to get reproducible results

# Grab the model_id for the top DL model, chosen by validation AUC
best_dl_model_id <- dl_gridperf@model_ids[[1]]
best_dl <- h2o.getModel(best_dl_model_id)

# Now let's evaluate the model performance on a test set
# so we get an honest estimate of top model performance
best_dl_perf <- h2o.performance(model = best_dl, 
                                newdata = test)
h2o.auc(best_dl_perf)
