############################################
## This script calculates growing degree days (GDD)
## using weather data from DownloadStationData.R
## then interpolates GDD for each population
## and growing season metrics.
############################################


##############################
## Load functions
##############################
library(fields) # Used for spatial interpolation of GDD for each population
library(zoo) # Used to impute missing data points for some weather stations in some days
library(dplyr)
library(tibble)
library(FSA)
library(reshape2)
source("idw.R")

############

##############################
## Load data
##############################
#setwd("~/2016 Queens/WeatherScraper/WeatherScraper/")
StnData<-read.csv("WeatherRawData/NOAAStationData.csv")
PopData<-read.csv("HerbariumPopData_wGDD_IDW.csv", header=T)



##############################
## Calculate GDD for 20 closest stations for each Pop
##############################

# For each population in the dataset
# Find nearby stations in NOAAData 
# load station growing degrees for each day (GD)
# NOTE: GD = (TMAX+TMIN)/20-8 and set GD=0 if GD<0


##GDeg : growing degree day per day
PopData$GD<-NA # Number of growing days above 5oC (Season Length)
PopData$GDs<-NA # Number of growing days from start of season to collection date
PopData$GDD<-NA # Standard Growing-Degree Days, as above
PopData$GDDs<-NA # GDD from start of season to date of collection
PopData$meanGDeg<-NA ##mean growing-degress per day over season
PopData$varGDeg<-NA ##variance of growing degrees per day over season
PopData$skewGDeg<-NA ## skew of """"
PopData$kurtGDeg<-NA ## kurtosis of """"
PopData$numStns <- NA ##number of stations used for the analysis




Cntr<-0

# For each year: 


for(year in (2008:2010)){ 
  
  # Open file with GD data
  GDFilePath<-paste0("WeatherRawData/NOAAStnsClose",year,".csv") 
  GDData<-read.csv(GDFilePath)
  for(Pop in PopData$Pop_Code[PopData$Year==year]){ # Cycle through pop_codes sampled in same year as GD data
    Cntr<-Cntr+1
    # Find names of nearby stations
    LocStns<-paste(unique(StnData$StationID[StnData$Pop_Code==Pop & StnData$Measure=="TMAX"]))
    # Subset GDData for stations of interest from Jan 1 to day of sampling
    # find all stations in station list, and cross with all stations in the year data
    PopGDData<-GDData[GDData$StationID %in% LocStns,]
    
    
    # Make data frame get geographic distance, lat, long for each station, subset to 20 stations if necessary
    # find all stations from station list based on population code, and only the stations that exist in yearly data set
    GeoDat<-unique(StnData[StnData$Pop_Code==Pop & StnData$StationID %in% unique(PopGDData$StationID),c("StationID", "Latitude", "Longitude", "Dist")])
    # reduce number of stations to closest 20
    if (nrow(GeoDat) > 20) { 
      GeoDat<- head(GeoDat[order(GeoDat$Dist),],20)
    }
    ## resubset again to reduce yearly data set to only the data on the twenty or less stations
    PopGDData<-GDData[GDData$StationID %in% GeoDat$StationID,]
    # reshape data frame so that each row is a day, and each column a station
    test<- dcast(PopGDData, Date ~ StationID, value.var = "GDeg")
    ## make days the row names
    test %>% remove_rownames %>% column_to_rownames(var="Date") -> test
    test<- test[colSums(!is.na(test)) > 0]
    
    ## double check here for stations in data set


    # GeoDat$GD<-NA ##Tota Growing Season Length (in Days)
    # GeoDat$GDs<-NA ##Growing Seaon Length to collection (in Days)
    # GeoDat$GDD<-NA ##Total Growing Degree Days over season (in Growing Degrees)
    # GeoDat$GDDs<-NA ##Growing Degree Days cumulative to time of collection (in Growing Degrees)
    # GeoDat$meanGDeg<-NA ##mean of growing degrees per day / total season length (GDD/GD)
    # GeoDat$varGDeg<-NA ##variance of growing degrees per day over the season 
    # GeoDat$skewGDeg<-NA ##skew of growing degrees per day over the season 
    # GeoDat$kurtGDeg<-NA ##variance of growing degrees per day over the season 
    # 
    
  # Growing degree day interpolation 
  
    test$GDeg <- NULL
    for (i in 1:365) { test$GDeg[i] <- idw(GeoDat$Dist, test[i,])}


   
    ##Calculate GD, GDs, GDD, GDDs values for each station
      ###
    yday<-as.numeric(PopData$yday[PopData$Pop_Code==Pop])
    test$Indicator <-FALSE
      ####Set days with positive GDD to true
    test$Indicator <- ifelse(test$GDeg > 0, TRUE, test$Indicator)
    ## Give sequences of growing degree days and non-growing days
    rletest<-rle(test$Indicator)
    ##put rle results into table
    length<-rletest$lengths
    value<-rletest$values
    df<-data.frame(length, value)
    df<- df %>% rownames_to_column()
    ##find values, but only start growing season if long warm period is March or later. 
    intervals<-df[which(df$length >= 10 & df$value ==TRUE & cumsum(df$length)>60),]
    ## row numbers for the beginning(min) and end(max) of the growing season
    rowdates<-c(min(as.numeric(intervals$rowname)), max(as.numeric(intervals$rowname)))  ## first value is beginning of season, second value is end of season
    df$cumDayminus<-pcumsum(df$length) ### these values are for beginning of season
    df$cumDay<-cumsum(df$length) ### these values are used for end of season
    begin <- as.numeric(df$cumDayminus[as.integer(rowdates[1])]) +1 ##first day of season, need one day added because cumDayminus means it starts at day before the actual start of season
    end <- as.numeric(df$cumDay[as.integer(rowdates[2])]) ##last day of season
      
      
      #Calculations for season length, and season to collection, moments of distribution
    GD <- (end - begin) + 1  ##season length, need +1 so start of season is included
    GDs <- yday-begin+1 ##length of season to collection, need +1 so start of season is included
    GDD <- sum(test$GDeg[begin:end]) ## GDD for the entire season
    GDDs <- sum(test$GDeg[begin:yday]) ##GDD from start of season to collection
      
    test <- test[c(begin:end),] ##subset data to only growing season
    meanGDeg <- mean(test$GDeg) ##mean of growing degrees per day
    varGDeg <- sum((test$GDeg - meanGDeg)^2)/GD ## var of growing degrees per day for growing season, no adjustion for sample size
    skewGDeg <- ((sum((test$GDeg - meanGDeg)^3))/GD) /(varGDeg)^(3/2) ##skewness, Fisher-Pearson (not adjusted for sample size)
    kurtGDeg <- ((sum((test$GDeg - meanGDeg)^4))/GD) /(varGDeg)^(4/2) -3 ##excess kurtosis for univariate data, 
      
      
      
      ##Data Values to Put into PopDat (all stations for each pop)
    PopData$GD[PopData$Pop_Code==Pop] <- GD
    PopData$GDs[PopData$Pop_Code==Pop] <- GDs
    PopData$GDD[PopData$Pop_Code==Pop] <- GDD
    PopData$GDDs[PopData$Pop_Code==Pop] <- GDDs
    PopData$meanGDeg[PopData$Pop_Code==Pop] <- meanGDeg
    PopData$varGDeg[PopData$Pop_Code==Pop] <- varGDeg
    PopData$skewGDeg[PopData$Pop_Code==Pop] <- skewGDeg
    PopData$kurtGDeg[PopData$Pop_Code==Pop] <- kurtGDeg
    PopData$numStns[PopData$Pop_Code==Pop] <- ncol(test) - 2 # minus GDeg column and Indicator column
   
    cat("***************\nIteration ",Cntr," of",length(PopData$Pop_Code),"\nYear: ",year,"\nPop: ",Pop,"\n",Sys.time(),"seconds","\nGD: ",PopData$GDD[PopData$Pop_Code==Pop],"\nGDDs: ",PopData$GDDs[PopData$Pop_Code==Pop],"\n***************")
    yday<-LocStns<-PopGDData<-GeoDat<-tps<-NA # clean up for next iteration of pop
    # SAVE output
    write.csv(PopData,"HerbariumPopData_GDD_byDay.csv",row.names=F)
  }
  GDData<-GDFilePath<-NA # Clean-up for next iteration of year
}

