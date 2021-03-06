\name{amsReliability-package}
\alias{amsReliability-package}
\alias{amsReliability}
\docType{package}
\title{amsReliability package}
\description{
\packageDescription{amsReliability}
}
\details{

A graphical user interface is provided in this package in order to help users to access the different analyses available. To start this GUI, user should use the \bold{RelAnalysis} function:

> \bold{RelAnalysis()}



Additionally, 3 functions are currently available within this package and can be accessed manually.

\bold{CreateExportFiles}: Automatically creates the exportfiles for a set of electromigration experiments
by using degradation and TCR files provided by Qualitau ACE and MIRA equipments.
All files should be placed in the folder where the function is run.
The function matches file names to create the exportfiles but is able to detect
if several conditions are stored in one file. One exportfile per condition is created.
If an exportfile is already present, user is asked if old files should be kept, replaced or if data have to be merged.
Times to failure are converted in seconds if they are provided in hours.

\bold{BlackAnalysis}: Extract Black's parameters from a set of electromigration experiments.
The experimental data as well as the resulting model are displayed and
can be saved. Extracted parameters are saved in a fit.txt file.

\bold{OxideTDDB}: Extract oxide lifetime parameters from a set of Time Dependant
Dielectric Breakdown (TDDB) experiments. The experimental data as well as the
resulting model are displayed and can be saved. Extracted parameters are saved
in a fit.txt file.}
\author{
\packageAuthor{amsReliability}

Maintainer: \packageMaintainer{amsReliability}
}
\references{

}

\keyword{ package }
\seealso{
}
\examples{

}
