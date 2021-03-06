################################################################################
###                                                                          ###
###    INFORMATIONS                                                          ###
###    ---------------------------------                                     ###
###                                                                          ###
###       PACKAGE NAME        amsReliability                                 ###
###       MODULE NAME         genericFunctions.r                             ###
###       VERSION             0.10.3                                           ###
###                                                                          ###
###       AUTHOR              Emmanuel Chery                                 ###
###       MAIL                emmanuel.chery@ams.com                         ###
###       DATE                2016/02/24                                     ###
###       PLATFORM            Windows 7 & Gnu/Linux 3.16                     ###
###       R VERSION           R 3.1.1                                        ###
###       REQUIRED PACKAGES   ggplot2, grid, MASS, nlstools, scales          ###
###       LICENSE             GNU GENERAL PUBLIC LICENSE                     ###
###                           Version 3, 29 June 2007                        ###
###                                                                          ###
###                                                                          ###
###    DESCRIPTION                                                           ###
###    ---------------------------------                                     ###
###                                                                          ###
###       This package is a collection of scripts dedicated to help          ###
###    the process reliability team of ams AG. It includes tools to          ###
###    quickly visualize data and extract model parameters in order          ###
###    to predict device lifetimes.                                          ###
###                                                                          ###
###       This module includes generic functions usable with every           ###
###    degradation mechanism.                                                ###
###                                                                          ###
###                                                                          ###
###    FUNCTIONS                                                             ###
###    ---------------------------------                                     ###
###                                                                          ###
###       CalculProbability         Standard deviation/weibit calculation    ###
###       Clean                     Remove TTF associated to bad devices     ###
###       CreateDataFrame           Place experimental data in a table       ###
###       CreateGraph               In charge of data representation         ###
###       ErrorEstimation           Calculation of confidence Intervals      ###
###       Ranking                   Calculation of fraction estimators       ###
###                                                                          ###
################################################################################


###### List of Constants  ######
k <- 1.38E-23 # Boltzmann
e <- 1.6E-19 # electron charge
################################


CalculLifeTime <- function(Model, Area, Stress, Temperature, Probability,  Law="BlackLaw")
# Calcul the lifetime of a device for a given condition (Temp/stress) at a given failure rate
# with a given model.
# For TDDB, area is transformed in m² whereas it is already given in m² for EM.
# Currently supports Black equation and a TDDB lifetime model.
{
    if (Law == "BlackLaw") {
        # Parameters Extraction
        A <- coef(Model)[1]
        n <- coef(Model)[2]
        Ea <-coef(Model)[3]
        Scale <- coef(Model)[4]

        TTF <- exp(A)*(Stress*0.001/Area)^(-n)*exp((Ea*e)/(k*(273.15+Temperature))+ Probability * Scale)

    } else if (Law == "TDDB"){
        # Parameters Extraction
        t0 <- coef(Model)[1]
        g <- coef(Model)[2]
        Ea <- coef(Model)[3]
        beta <- coef(Model)[4]

        TTF <- exp(t0)*exp(-g*Stress)*exp((Ea*e)/(k*(Temperature+273.15)))*(Area*1E-12)^(-1/beta)*exp(Probability/beta)

    }
    return(as.numeric(TTF))
}


CalculProbability <- function(Probability, Scale="Lognormal")
# Given a vector Probability of probabilities, the function calculates
# the correspondence in standard deviations for the Lognormal case.
# Calculation of the Weibit is made for the Weibull case.
{
  if (Scale=="Weibull") {
      Proba <- log(-log(1-Probability)) # Weibull
  } else {
      Proba <- qnorm(Probability) # Lognormal
  }
  return(Proba)
}


Clean <- function(DataTable)
# Take a datatable provided by CreateDataFrame and clean it.
# Cleaning of the data. Only lines with a status 1 or 0 are kept.
# Finally TTF are sorted from the smallest to the largest.
# Qualitau column name is 'Failed'
{
    CleanedTable <- DataTable[DataTable$Status==1 | DataTable$Status==0,]
    CleanedTable <- CleanedTable[order(CleanedTable$"TTF"),] # Sort TTF
    # Remove ghost levels: levels were no samples are listed anymore.
    CleanedTable <- droplevels(CleanedTable)
    return(CleanedTable)
}


CreateDataFrame <- function(TTF, Status, Condition, Stress, Temperature, Scale="Lognormal", Dimension = 1)
# Creation of the dataframe assembling the TTF, the status of the samples,
# the probability, the condition (stickers for charts),
# the stress condition and the temperature used durng the stress.
# The probability is calculated according to Lognormal or Weibull distribution.
# Data are given clean.
# Data(TTF,Status,Probability,Conditions,Stress,Temperature, Dimension)
{
    rk <- Ranking(TTF) # Fraction estimator calculation
    if (Scale=="Weibull") {
        Proba <- CalculProbability(rk,Scale="Weibull") # Probability calculation Weibull
    } else {
        Proba <- CalculProbability(rk,Scale="Lognormal") # Probability calculation Lognormal
    }
    # Generation of the final data frame
    DataTable <- data.frame('TTF'=TTF,'Status'=Status,'Probability'=Proba,'Conditions'=Condition, 'Stress'=Stress, 'Temperature'=Temperature, 'Dimension'=Dimension)
    return(DataTable)
}


CreateModelDataTable <- function(Model, ListConditions, Area, Law="BlackLaw", Scale="Lognormal")
# Return a theoretical lifetime for a given set of Conditions and a given model.
# Result is returned in a dataframe.
# Currently supported model are Black equation and a TDDB lifetime model.
{
    # Initialisation
    ModelDataTable <- data.frame()
    # y axis points are calculated. (limits 0.01% -- 99.99%) Necessary to have nice confidence bands.
    Proba <- seq(CalculProbability(0.0001, Scale), CalculProbability(0.9999, Scale), 0.05)

    # Extraction of temperature and stress conditions
    Temperature <- sapply(ListConditions,function(x){strsplit(x,split="[mAV]*/")[[1]][2]})
    Temperature <- as.numeric(sapply(Temperature,function(x){substr(x,1, nchar(x)-2)}))
    Stress <- as.numeric(sapply(ListConditions,function(x){strsplit(x,split="[mAV]*/")[[1]][1]}))

    for (i in seq_along(Temperature)){

        # TTF calculation
        TTF <- CalculLifeTime(Model, Area, Stress[i], Temperature[i], Proba, Law)
        # Dataframe creation
        ModelDataTable <- rbind(ModelDataTable, data.frame('TTF'=TTF,'Status'=1,'Probability'=Proba,'Conditions'=ListConditions[i],'Stress'=Stress[i],'Temperature'=Temperature[i], 'Area'=Area))

    }
    return(ModelDataTable)
}


ErrorEstimation <- function(ExpDataTable, ModelDataTable, ConfidenceValue=0.95, Scale="Lognormal")
# Generation of confidence intervals
# Based on Kaplan Meier estimator and Greenwood confidence intervals
{
    # list of conditions
    ListConditions <- levels(ExpDataTable$Conditions)
    # DataFrame initialisation
    ConfidenceDataTable <- data.frame()

    if (length(ListConditions) != 0){

          for (condition in ListConditions){

              NbData <- length(ExpDataTable$TTF[ExpDataTable$Conditions == condition & ExpDataTable$Status == 1])
              if (NbData > 30) {
                  mZP_Value <- qnorm((1 - ConfidenceValue) / 2) # Normal case. Valid if sample size > 30.
              } else {
                  mZP_Value <- qt((1 - ConfidenceValue) / 2, df=(NbData -1) ) # t-test statistic for low sample size
              }

              if (Scale == "Weibull"){
                  CDF <- 1-exp(-exp(ModelDataTable$Probability[ModelDataTable$Conditions == condition]))
                  sef <- sqrt(CDF * (1 - CDF)/NbData)
                  LowerLimit <- log(-log(1-(CDF - sef * mZP_Value)))
                  HigherLimit <- log(-log(1-(CDF + sef * mZP_Value)))

              } else {
                  CDF <- pnorm(ModelDataTable$Probability[ModelDataTable$Conditions == condition])
                  sef <- sqrt(CDF * (1 - CDF)/NbData)
                  LowerLimit <- qnorm(CDF - sef * mZP_Value)
                  HigherLimit <- qnorm(CDF + sef * mZP_Value)
              }

              ConfidenceDataTable <- rbind(ConfidenceDataTable, data.frame('TTF'=ModelDataTable$TTF[ModelDataTable$Conditions == condition],
                                                                            'LowerLimit'=LowerLimit,'HigherLimit'=HigherLimit,'Conditions'=condition))
        }
    }
    return(ConfidenceDataTable)
}


FitDistribution <- function(DataTable,Scale="Lognormal")
# Extract simple distribution parameters (MTTF, scale) and return
# a ModelDataTable to plot the theoretical distribution
# Use fitdistr function
{
    # For each condtion we estimate a theoretical distribution
    # A condition needs to have at least one good sample to be counted
    ListConditions <- levels(DataTable$Conditions[DataTable$Status==1,drop=TRUE])

    # Initialisation of ModelDataTable
    ModelDataTable <- data.frame()

    for (ModelCondition in ListConditions){

        # Stress and Temperature stickers
        ModelStress <- DataTable$Stress[DataTable$Conditions==ModelCondition][1]
        ModelTemperature <- DataTable$Temperature[DataTable$Conditions==ModelCondition][1]

        # x axis limits are calculated
        lim <- range(DataTable$TTF[DataTable$Conditions==ModelCondition])
        lim.high <- 10^(ceiling(log(lim[2],10)))
        lim.low <- 10^(floor(log(lim[1],10)))
        # Generation of a vector for the calculation of the model. 200pts/decades
        x <- 10^seq(log(lim.low,10),log(lim.high,10),0.005)


        # Model calculation with the experimental TTF
        if (Scale=="Weibull") { # Weibull
              fit <- fitdistr(DataTable$TTF[DataTable$Conditions==ModelCondition & DataTable$Status==1],"weibull")
              fitShape <- fit$estimate[1]  # Beta
              fitScale <- fit$estimate[2]  # Characteristic time (t_63%)
              y <- CalculProbability(pweibull(x, fitShape, fitScale),"Weibull")
              # Display of Model parameters
              print(paste("Condition ",ModelCondition, " Beta= ", fitShape, " t63%=", fitScale,sep=""))

        } else { # Lognormale
              fit <- fitdistr(DataTable$TTF[DataTable$Conditions==ModelCondition & DataTable$Status==1],"lognormal")
              fitScale <- fit$estimate[1]  # meanlog
              fitShape <- fit$estimate[2]  # sdlog
              y <- CalculProbability(plnorm(x, fitScale, fitShape),"Lognormale")
              # Display of Model parameters
              print(paste("Condition ",ModelCondition, " Shape= ", fitShape, " MTTF=", exp(fitScale),sep=""))
        }

        # ModelDataTable creation
        ModelDataTable <- rbind(ModelDataTable, data.frame('TTF'=x,'Status'=1,'Probability'=y,'Conditions'=ModelCondition,'Stress'=ModelStress,'Temperature'=ModelTemperature) )
    }
    return(ModelDataTable)
}


FitResultsDisplay <- function(Model, DataTable, DeviceID)
# Given a model and an experimental dataset
# Return the parameters of the model and the residual error
# Save the information in a fit.txt file
{
    CleanDataTable <- DataTable[DataTable$Status==1,]
    # Residual Sum of Squares
    RSS <- sum(resid(Model)^2)
    # Total Sum of Squares: TSS <- sum((TTF - mean(TTF))^2))
    TSS <- sum(sapply(split(CleanDataTable[,1],CleanDataTable$Conditions),function(x) sum((x-mean(x))^2)))
    Rsq <- 1-RSS/TSS # R-squared measure

    # Drawing of the residual plots
    plot(nlsResiduals(Model))
    # Display of fit results
    cat(DeviceID,"\n")
    print(summary(Model))
    cat(paste("Residual squared sum: ",RSS, "\n",sep=""))
    cat(paste("Log likelihood: ",logLik(Model), "\n",sep=""))
    cat(paste("Akaike information criterion: ",AIC(Model), "\n",sep=""))
    cat(paste("Bayesian information criterion: ",BIC(Model), "\n",sep=""))
    # Save in a file
    capture.output(summary(Model),file="fit.txt")
    cat("Residual Squared sum:\t",file="fit.txt",append=TRUE)
    cat(RSS,file="fit.txt",append=TRUE)
    cat(paste("\nLog likelihood\t", logLik(Model), "\n", sep=""), file="fit.txt", append=TRUE)
    cat(paste("Akaike information criterion\t", AIC(Model), "\n", sep=""), file="fit.txt", append=TRUE)
    cat(paste("Bayesian information criterion\t", BIC(Model), "\n", sep=""), file="fit.txt", append=TRUE)
    cat("\n \n",file="fit.txt",append=TRUE)
    cat("Experimental Data:",file="fit.txt",append=TRUE)
    cat("\n",file="fit.txt",append=TRUE)
}


KeepOnlyFailed <- function(dataTable)
# Modelization and error calculation is only performed on failed samples
# Remove all the other samples and drop the ghost levels.
{
    dataTable <- droplevels(dataTable[dataTable$Status == 1,])
    return(dataTable)
}


ModelFit <- function(dataTable, Law="BlackLaw")
# Perform a least square fit on an experimental dataset
# Return a model containing the parameters and the residuals.
{
    if (Law == "BlackLaw") {
        # Black model / Log scale: use of log10 to avoid giving too much importance to data with a high TTF
        Model <- nls(log10(TTF) ~ log10(exp(A)*(Stress*1E-3/Area)^(-n)*exp((Ea*e)/(k*(Temperature+273.15))+Scale*Probability)), dataTable,
                start=list(A=30,n=1,Ea=0.7,Scale=0.3),control= list(maxiter = 50, tol = 1e-7))#, minFactor = 1E-5, printEval = FALSE, warnOnly = FALSE))#,trace = T)
    } else if (Law == "TDDB"){
        # TDDB model / Log scale: use of log10 to avoid giving too much importance to data with a high TTF
        Model <- nls(log10(TTF) ~ log10(exp(t0)*exp(-g*Stress)*exp((Ea*e)/(k*(Temperature+273.15)))*(Area*1E-12)^(-1/beta)*exp(Probability/beta)), dataTable,
                start=list(t0=30,g=1,Ea=0.2,beta=1),control= list(maxiter = 50, tol = 1e-6))#, minFactor = 1E-5, printEval = FALSE, warnOnly = FALSE))#,trace = T)
    }
    return(Model)
}


Ranking <- function(TTF)
# Fraction estimator calculation
# rk(i)=(i-0.3)/(n+0.4)
# TTF is a vector.
{
    # ties.method="random" handles identical TTFs and provide a unique ID
    rk <- (rank(TTF, ties.method="random")-0.3)/(length(TTF)+0.4)
}


SaveData2File <- function(data, file)
# Save Data to a file
{
    capture.output(data, file=file, append=TRUE)
}


SelectFiles <- function(Filters=GenericFilters)
# Allow graphical selection of multiple files.
# Return them as a list.
{
    # Create the Path.
    # This path is used to enter the working directory directory.
    # False file 'select a file' force the entry in the wd.
    path2Current <- paste(getwd(), "/", "Select_a_file", sep="")

    # Generic filters for file selection
    GenericFilters <- matrix(c("All files", "*", "Export Files", "*exportfile.txt", "Text", ".txt"),3, 2, byrow = TRUE)

    # Gui for file selection
    selection <- tk_choose.files(default = path2Current, caption = "Select files",
                            multi = TRUE, filters = Filters, index = 1)

    if (Sys.info()[['sysname']] == "Linux"){
        # On  Linux, first file is removed as it is empty. Coming from path2Current
        selection <- selection[-1]
    }

    return(selection)
}


SelectFilesAdvanced <- function(Filters)
# Allow graphical selection of multiple files
# Return the file name only
# set the working directory to the directory where the file where selected.
{

    if (missing(Filters)){
        selection <- SelectFiles()
    } else {
        selection <- SelectFiles(Filters)
    }

    if (length(selection) == 0){
        stop("File selection is empty.")
    }

    # Cleaning to remove the path and keep only the filename (last item)
    listFiles <- sapply(selection, basename)
    # Rename to avoid ugly naming of the list
    names(listFiles) <- rep("", length(listFiles))
    # new working path
    newWD <- dirname(selection[1])
    setwd(newWD)

    return(listFiles)
}


SortConditions <- function(listConditions)
  # Sort a list of conditions to avoid 6mA being bigger as 14mA
  # Return a list of Conditions sorted.
  # explode a condition in a list of number and sort them from 
  # right to left.
  # Needs stringr package
{
  table <- data.frame()
  for (condition in listConditions){
    table <- rbind(table, data.frame(condition, t(str_extract_all(condition, pattern="[0-9.]{1,}")[[1]])))
  }
  
  
  # Sort strating by last column
  for (i in seq(dim(table)[2], 2) ){ # we start from last colum and stop at column 2
    table <-  table[order(as.numeric(as.character(table[[i]]))),]
  }
  
  return(as.character(table$condition))
}


OrderConditions <- function(DataTable)
# Order a list of conditions to avoid 6mA being
# bigger as 14mA.
# Return a vector of indice.
{
    SortedListConditions <- SortConditions(levels(DataTable$Conditions))
    VecIndices <- c()
    for (condition in SortedListConditions){
        VecIndices <- c(VecIndices, which(DataTable$Conditions == condition))
    }
    return(VecIndices)
}


clc <- function()
# Clear screen function for terminal
{
    return(cat("\n\n\n\n\n\n\n\n"))
    # return(cat("\014"))
}
