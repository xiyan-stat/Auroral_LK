empirical <- function(doy, dFdt, hemi, premodel = "premodel") {
  # "premodel": folder containing auroral coefficient files
  
  stopifnot(is.numeric(doy) & length(doy) == 1 & is.numeric(dFdt) & hemi %in% c("N", "S") & is.character(premodel))
  
  # function to calculate seasonal weights of current day, valid for northern hemisphere
  # to calculate seasonal weights for southern hemisphere, call with 365-doy
  season_weights <- function(doy) {
    wt <- array(data = 0, dim = 4)
    if (doy < 79) {
      wt[2] <- 1 - (79 - doy) / 90
      wt[1] <- 1 - wt[2]
    } else if (select_doy < 171) {
      wt[3] <- 1 - (171 - doy) / 92
      wt[2] <- 1 - wt[3]
    } else if (select_doy < 263) {
      wt[4] <- 1 - (263 - doy) / 92
      wt[3] <- 1 - wt[4]
    } else if (select_doy < 354) {
      wt[1] <- 1 - (354 - doy) / 91
      wt[4] <- 1 - wt[1]
    } else {
      wt[2] <- 1 - (79 - (doy-365)) / 90
      wt[1] <- 1 - wt[2]
    }
    return (wt)
  }
  
  season <- c("winter", "spring", "summer", "fall")
  type <- c("diff", "mono", "wave")
  
  nszn <- length(season)
  ntype <- length(type)
  nmlt <- 96
  nmlat <- 160
  
  # mlt and mlat at the corresponding grid points
  mlt <- seq(from = 0, to = 24, length.out = nmlt + 1)
  mlt <- mlt[1: nmlt]
  mlat <- seq(from = 50, to = 90, length.out = nmlat/2 + 1)
  mlat <- mlat[1: (nmlat/2)]
  if (hemi == "S") mlat <- -mlat
  
  prob_coeff_1 <- array(dim = c(nszn, ntype, nmlt, nmlat))
  prob_coeff_2 <- array(dim = c(nszn, ntype, nmlt, nmlat))
  energy_coeff_1 <- array(dim = c(nszn, ntype, nmlt, nmlat))
  energy_coeff_2 <- array(dim = c(nszn, ntype, nmlt, nmlat))
  number_coeff_1 <- array(dim = c(nszn, ntype, nmlt, nmlat))
  number_coeff_2 <- array(dim = c(nszn, ntype, nmlt, nmlat))
  
  # read in all coefficients
  for (iszn in 1: nszn) {
    for (itype in 1: ntype) {
      prob_coeffs <- read.table(file = paste(premodel, "/", season[iszn], "_prob_b_", type[itype], ".txt", sep = ""), skip = 1, nrows = nmlt*nmlat)
      energy_coeffs <- read.table(file = paste(premodel, "/", season[iszn], "_", type[itype], ".txt", sep = ""), skip = 1, nrows = nmlt*nmlat)
      number_coeffs <- read.table(file = paste(premodel, "/", season[iszn], "_", type[itype], "_n.txt", sep = ""), skip = 1, nrows = nmlt*nmlat)
      for (imlt in 1: nmlt) {
        prob_coeff_1[iszn, itype, imlt, ] <- prob_coeffs$V1[((imlt-1)*nmlat + 1): (imlt*nmlat)]
        prob_coeff_2[iszn, itype, imlt, ] <- prob_coeffs$V2[((imlt-1)*nmlat + 1): (imlt*nmlat)]
        energy_coeff_1[iszn, itype, imlt, ] <- energy_coeffs$V3[((imlt-1)*nmlat + 1): (imlt*nmlat)]
        energy_coeff_2[iszn, itype, imlt, ] <- energy_coeffs$V4[((imlt-1)*nmlat + 1): (imlt*nmlat)]
        number_coeff_1[iszn, itype, imlt, ] <- number_coeffs$V3[((imlt-1)*nmlat + 1): (imlt*nmlat)]
        number_coeff_2[iszn, itype, imlt, ] <- number_coeffs$V4[((imlt-1)*nmlat + 1): (imlt*nmlat)]
      }
    }
  }
  
  nt <- length(dFdt)
  newdim <- c(nt, nszn, ntype, nmlt, nmlat)
  dFdt_rep <- array(data = rep(dFdt, times = nszn*ntype*nmlt*nmlat), dim = newdim)
  
  # simplified probability calculation
  prob_effect <- array(data = rep(prob_coeff_1, each = nt), dim = newdim) + array(data = rep(prob_coeff_2, each = nt), dim = newdim) * dFdt_rep
  prob_effect[prob_effect < 0] <- 0
  prob_effect[prob_effect > 1] <- 1
  
  # energy flux
  energy_all <- array(data = rep(energy_coeff_1, each = nt), dim = newdim) * prob_effect + array(data = rep(energy_coeff_2, each = nt), dim = newdim) * dFdt_rep
  energy_all[energy_all < 0] <- 0
  energy_all[energy_all > 10] <- 0.5
  energy_all[energy_all > 5] <- 5
  
  # number flux
  number_all <- array(data = rep(number_coeff_1, each = nt), dim = newdim) * prob_effect + array(data = rep(number_coeff_2, each = nt), dim = newdim) * dFdt_rep
  number_all[number_all < 0] <- 0
  number_all[number_all > 2e10] <- 0
  number_all[number_all > 2e9] <- 1e9
  
  # seasonal weights
  if (hemi == "S") doy <- 365 - doy
  wt <- season_weights(doy)
  
  # weighted energy/number flux
  energy <- array(data = 0, dim = c(nt, ntype, nmlt, nmlat))
  number <- array(data = 0, dim = c(nt, ntype, nmlt, nmlat))
  for (iszn in 1: nszn) {
    energy <- energy + wt[iszn] * energy_all[, iszn, , , ]
    number <- number + wt[iszn] * number_all[, iszn, , , ]
  }
  
  # 50 <= mlat < 90, (nmlat/2 + 1): nmlat
  if (hemi == "N") {
    energy <- energy[, , , (nmlat/2 + 1): nmlat]
    number <- number[, , , (nmlat/2 + 1): nmlat]
  }
  
  # -50 >= mlat > -90, 1: (nmlat/2)
  if (hemi == "S") {
    energy <- energy[, , , 1: (nmlat/2)]
    number <- number[, , , 1: (nmlat/2)]
  }
  
  # convert to energy flux and mean energy
  flux <- energy
  energy <- flux / number / 1.6e-9
  energy[is.infinite(energy)] <- 0
  
  return (list(type = type, mlat = mlat, mlt = mlt, flux = flux, energy = energy))
}

#############################################################################################
f <- read.table(file = "omni2.lst")
time <- seq(from = 0, to = 23, by = 1)
hour <- (f$V2 - 51) * 24 + f$V3
dFdt <- f$V6^(4/3) * sqrt(f$V4^2 + f$V5^2)^(2/3) * abs(sin(atan2(f$V4, f$V5)/2))^(8/3)
dFdt <- approx(x = hour, y = dFdt, xout = time)$y
emp <- empirical(doy = 51, dFdt, hemi = "N", premodel = "premodel")

# empirical data requires a lot preprocessing
# valid <- emp$mlat < 70
# emp$mlat <- emp$mlat[valid]
# emp$flux <- emp$flux[, , , valid]
# emp$energy <- emp$energy[, , , valid]
coor <- expand.grid(emp$mlt * pi/12, pi/2 - emp$mlat * pi/180)
t4 <- coor$Var1
r4 <- coor$Var2
x_emp <- r4 * cos(t4)
y_emp <- r4 * sin(t4)

# northern emp flux data
nlat_emp <- length(emp$mlat)
nlon_emp <- length(emp$mlt)

data.flux.emp_n <- tibble(
  flux = as.vector(emp$flux[,1,,]) * 7,   # adjust the measurement of empirical flux
  x = rep(as.vector(x_emp), 24),
  y = rep(as.vector(y_emp), 24),
  time = rep(0:23, each=nlat_emp*nlon_emp)*60,
  source = "emp"
) %>%
  filter(!is.na(flux)) %>%              
  select(flux, x, y, time, source)

#############################################
# plot
data.flux.emp_n %>%
  filter(time %in% 660) %>%  
  ggplot(aes(x = x, y = y)) +
  geom_point(aes(colour = flux), size=0.1)+
  scale_colour_distiller(palette = "Spectral")+
  theme_bw()