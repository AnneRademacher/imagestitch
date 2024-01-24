close("*");

//set some options
setOption("ExpandableArrays", true);
setBatchMode(true);

//define some functions
/*function ArrayUnique(array) {
	array 	= Array.sort(array);
	array 	= Array.concat(array, 999999);
	uniqueA = newArray();
	i = 0;	
   	while (i<(array.length)-1) {
		if (array[i] == array[(i)+1]) {
			//print("found: "+array[i]);			
		} else {
			uniqueA = Array.concat(uniqueA, array[i]);
		}
   		i++;
   	}
	return uniqueA;
}*/

function GetTimeString() {
	MonthNames = newArray("Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec");
	DayNames = newArray("Sun", "Mon","Tue","Wed","Thu","Fri","Sat");
	getDateAndTime(year, month, dayOfWeek, dayOfMonth, hour, minute, second, msec);
	TimeString = "Date: "+DayNames[dayOfWeek]+" ";
	if (dayOfMonth<10) {TimeString = TimeString+"0";}
	TimeString = TimeString+dayOfMonth+"-"+MonthNames[month]+"-"+year+"\nTime: ";
	if (hour<10) {TimeString = TimeString+"0";}
	TimeString = TimeString+hour+":";
	if (minute<10) {TimeString = TimeString+"0";}
	TimeString = TimeString+minute+":";
	if (second<10) {TimeString = TimeString+"0";}
	TimeString = TimeString+second;
	return TimeString;
}

function GetShortTimeString() {
	getDateAndTime(year, month, dayOfWeek, dayOfMonth, hour, minute, second, msec);
	ShortTimeString = "" + year + "-";
	month = month + 1;
	if (month < 10) {ShortTimeString = ShortTimeString + "0";}
	ShortTimeString = ShortTimeString + month + "-";
	if (dayOfMonth<10) {ShortTimeString = ShortTimeString+"0";}
	ShortTimeString = ShortTimeString+dayOfMonth+"_";
	if (hour<10) {ShortTimeString = ShortTimeString+"0";}
	ShortTimeString = ShortTimeString+hour+"h";
	if (minute<10) {ShortTimeString = ShortTimeString+"0";}
	ShortTimeString = ShortTimeString+minute+"m";
	if (second<10) {ShortTimeString = ShortTimeString+"0";}
	ShortTimeString = ShortTimeString+second+"s";
	return ShortTimeString;
}

function SetLUTResetContrast(LUT){
	//selectWindow(stack);
	Stack.getDimensions(width, height, channels, slices, frames);
	for(j=0; j<channels; j++){
		Stack.setChannel(j+1);
		run(LUT);
		setMinAndMax(0, 65535);				
		}
	}

// get directory and create and open a log file
dir = getDirectory("Choose the directory of your experiment (containing the ims files and a metadata file");
infiles = getFileList(dir);
logfile = File.open(dir + GetShortTimeString() + "_log.txt");
print(logfile, "Run started:\n" + GetTimeString());
print(logfile, "Analyzing data in " + dir);

//get gain file for flatfield correction
correctdir = "/Volumes/sd17B002/Microscopy-Dragonfly/Image-Analysis/Flat-Field-Correction/2022-05-16/";
correct = getFileList(correctdir);

Dialog.create("Select gain image for flatfield correction");
Dialog.addChoice("Gain:", correct);
Dialog.show();
gain = Dialog.getChoice();
print(logfile, "Using " + gain + " for flatfield correction");

//initialize some arrays
meta = newArray;
laser_on = newArray;
wavelengths = newArray;

//extract the channel configuration from the metadata file
for(i=0; i<infiles.length; i++){
	if (endsWith(infiles[i], "metadata.txt")){
		meta = Array.concat(meta,infiles[i]);
		}
	}

if (meta.length == 0){
	exit("No metadata file found.");
	} else {
		if (meta.length > 1){
		Dialog.create("Multiple metadata files were found. Select one to extract the channel information from.");
		Dialog.addChoice("metadata file:", meta);
		Dialog.show();
		meta = Dialog.getChoice();
		print(logfile, "Using " + meta + " to extract channel information.");
		meta = dir + meta;
		}else{
			meta = dir + meta[0];
			}
		}

ctrl=0;
montage=0;
lns = split(File.openAsString(meta), "\n");
for (j=0; j<lns.length; j++){
	lns[j]=replace(lns[j], "\t", "");
	
	//extract existing laser lines and their wavelengths
	if (startsWith(lns[j], "{DisplayName=Laser Wavelength")) {
		lambda=split(lns[j],"=");
		laser=replace(lambda[1], "Laser Wavelength ", "");
		laser=replace(laser, ", Value", "");
		laser=parseInt(laser);
		lambda=replace(lambda[2], "}", "");
		lambda=parseInt(lambda);
		List.set(laser, lambda);
		} else if (lns[j] == "[Imaging Modes In Protocol]"){
			ctrl=1;
			} else if (lns[j] == "[FieldMontageProtocolSpecification]"){
				montage=1;
				}
		
	//extract used laser lines and stitch parameters (i. e. tiling dimensions)
	if (startsWith(lns[j], "{DisplayName=Laser") && endsWith(lns[j], "True}") && ctrl == 0){
		temp = replace(lns[j], "\\{DisplayName=Laser ", "");
		temp = replace(temp, ", Value=True}", "");
		laser_on = Array.concat(laser_on, parseInt(temp));
		} else if (startsWith(lns[j], "Rows") && montage == 1){
			temp = replace(lns[j],"Rows=", "");
			y_grid = temp;
			} else if (startsWith(lns[j], "Columns") && montage == 1){
				temp = replace(lns[j], "Columns=", "");
				x_grid = temp;
				} else if (startsWith(lns[j], "Overlap") && montage == 1){
					temp = replace(lns[j], "Overlap=", "");
					o=temp;
					}
	}
print(logfile, "Stitching a "+ x_grid + " x " + y_grid + " image with " + o + "% overlap between the tiles");

//remove first element of laser_on --> when using the twin cam, the Zyla laser is listed twice as on
laser_on = Array.slice(laser_on,1);     

//get the list with all existing lasers and their corresponding wavelengths
laser = List.getList;

for (n=0; n<laser_on.length; n++){
	wavelengths = Array.concat(wavelengths,List.get(laser_on[n]));
	}

//choose the channel to be used for stitching (usually DAPI)
Dialog.create("Select channel to be extracted and used for stitching");
Dialog.addChoice("Stich channel (excitation wavelength in nm):", wavelengths);
Dialog.show();
stitch = Dialog.getChoice();
print(logfile, "Extracting the " + stitch + " nm channel for stitching");

//get the index of the channel to be used for stitching (usually the last for DAPI)
for (n=0; n<wavelengths.length; n++){
	if (wavelengths[n]==stitch){
		stitch_index = n+1;
		}
	}

//get the stitch parameters from input (same for all wells)
/*Dialog.create("Specify stitch parameters");
Dialog.addNumber("Width (x):", 11);
Dialog.addNumber("Height (y):", 11);
Dialog.addNumber("Overlap:", 10);
Dialog.show();
x_grid = Dialog.getNumber();
y_grid = Dialog.getNumber();
o = Dialog.getNumber();*/

//create some folders for results
subdir = dir;
filelist = getFileList(subdir);
//outdir = dirname+"/_TIF_Stacks/";
outdirmax = subdir + "/_TIF_MaxProj/";
outdirmaxch = outdirmax + "/_" + stitch + "/";
outdirmaxchcorr = outdirmaxch + "/_flatfield_corrected/";
fused = subdir + "/_Fused/";
//File.makeDirectory(outdir);
File.makeDirectory(outdirmax);
File.makeDirectory(outdirmaxch);
File.makeDirectory(fused);
		
//do the tiff-converstation, max proj and channel extraction for the subdirectories, i. e. the wells
for(i=0; i<filelist.length; i++) {
	if (endsWith(filelist[i], ".ims")){
		filenm = subdir+filelist[i];
		check = outdirmax+"MAX_"+replace(filelist[i], ".ims", ".tif");
		if (File.exists(check)){
			open(check);
			} else {
				print("Converting file "+(i+1)+"/"+filelist.length+" ("+filelist[i]+")");
				run("Bio-Formats (Windowless)", "open=filenm");
				SetLUTResetContrast("Grays");
				//saveAs("Tiff", outdir+list[i]);
				run("Z Project...", "projection=[Max Intensity]");
				setMinAndMax(0, 65535);
				saveAs("Tiff", outdirmax+"MAX_"+filelist[i]);
				}
			run("Duplicate...", "duplicate channels=stitch_index-stitch_index");
			setMinAndMax(0, 65535);
			saveAs("Tiff", outdirmaxch+stitch+"nm_MAX_"+filelist[i]);
			rename("RawDAPI");
			setMinAndMax(0, 65535);

		if (stitch == 405){
			print("Correcting flatfield for "+stitch+" nm channel for "+filelist[i]);
			File.makeDirectory(outdirmaxchcorr);
			// calculate the corrected Image (RawImage-Dark) x Gain
			open(correctdir+gain);
			rename("gain");
			setMinAndMax(0, 65535);
			open(correctdir+"EMCCD2darkCounts.tif");
			rename("dark");
			setMinAndMax(0, 65535);
			imageCalculator("Subtract create", "RawDAPI", "dark");
			rename("raw_minus_dark");
			run("32-bit");
			setMinAndMax(0, 65535);
			imageCalculator("Multiply create 32-bit", "raw_minus_dark" , "gain");
			rename("corr_Image");
			setMinAndMax(0, 65535);
			run("16-bit");
			setMinAndMax(0, 65535);
			saveAs("Tiff", outdirmaxchcorr+stitch+"nm_MAX_ffcorr_"+filelist[i]);
			}
		close("*");
		} else {
			print("skipped "+filelist[i]);
			}
	}
//extract index of first image (..._F????.tif)
maxlist = getFileList(outdirmaxch);
filenm = maxlist[0];
init = split(maxlist[0], "_");
init = init[init.length-1];
init = replace(init, "F", "");
init = replace(init, ".tif", "");
init = parseInt(init);

filenm = replace(filenm, "[0-9]{4}.tif", "\\{iiii\\}.tif");
filenm = replace(filenm, "[0-9]{3}.tif", "\\{iii\\}.tif");
filenm = replace(filenm, "[0-9]{2}.tif", "\\{ii\\}.tif");
filenm = replace(filenm, "[0-9]{1}.tif", "\\{i\\}.tif");
filenm = replace(filenm, "MAX", "MAX_ffcorr");

//run stitching on selected channel (computing perfect overlap)
run("Grid/Collection stitching", "type=[Grid: snake by columns] order=[Up & Right] grid_size_x=x_grid grid_size_y=y_grid tile_overlap=o first_file_index_i=init directory=" + outdirmaxchcorr + " file_names=" + filenm + " output_textfile_name=TileConfiguration.txt fusion_method=[Do not fuse images (only write TileConfiguration)] regression_threshold=0.30 max/avg_displacement_threshold=2.5 absolute_displacement_threshold=3.5 compute_overlap subpixel_accuracy computation_parameters=[Save computation time (but use more RAM)] image_output=[Fuse and display]");

//modify file names and incorrect large tile displacements in output tile configuration file
lns = split(File.openAsString(outdirmaxchcorr + "TileConfiguration.registered.txt"), "\n");
lns_init = split(File.openAsString(outdirmaxchcorr + "TileConfiguration.txt"), "\n");
outfile = outdirmax + "TileConfiguration.registered.clean.txt";
outfile2 = outdirmaxchcorr + "TileConfiguration.registered.clean.txt";
File.delete(outfile);
File.delete(outfile2);

for (k=0; k<lns.length; k++){
	if (startsWith(lns[k], stitch)){
		lns[k] = replace(lns[k], stitch + "nm_MAX_ffcorr", "MAX");
		line = split(lns[k], ";");
		coord = split(line[2], ",");
		x = replace(coord[0], "\\(", "");
		y = replace(coord[1], "\\)", "");
		x = parseFloat(x);
		y = parseFloat(y);
		line_init = split(lns_init[k], ";");
		coord = split(line_init[2], ",");
		x_init = replace(coord[0], "\\(", "");
		y_init = replace(coord[1], "\\)", "");
		x_init = parseFloat(x_init);
		y_init = parseFloat(y_init);
		if (abs(x - x_init) + abs(y - y_init) > 20000){
			print(logfile, "DISPLACED TILE: "+line[0]);
			print(logfile, "displacement (sum of abs(delta(x)) and abs(delta(y)) in pixels): " + abs(x - x_init) + abs(y - y_init));
			coord = " (" + x_init + ", " + y_init + ")";
			line[2] = coord;
			lns[k] = String.join(line, ";");
			}
		File.append(lns[k], outfile); 
		lns[k] = replace(lns[k], "MAX", stitch+"nm_MAX_ffcorr");
		File.append(lns[k], outfile2);
		} else {
			File.append(lns[k], outfile);
			File.append(lns[k], outfile2);
			}
	}
	
//apply stitch positions to maximum stacks
run("Grid/Collection stitching", "type=[Positions from file] order=[Defined by TileConfiguration] directory=" + outdirmax + " layout_file=TileConfiguration.registered.clean.txt fusion_method=[Linear Blending] regression_threshold=0.30 max/avg_displacement_threshold=2.50 absolute_displacement_threshold=3.50 subpixel_accuracy computation_parameters=[Save computation time (but use more RAM)] image_output=[Fuse and display]");

//make a nice stack with the fused images
SetLUTResetContrast("Grays");
Stack.getDimensions(width, height, channels, slices, frames);
run("Split Channels");
filenm = replace(filenm, stitch + "nm_MAX_ffcorr", "MAX");
filenm = replace(filenm, "_F\\{i{1,4}\\}.tif", "_Fused_");
for (i=0; i<channels; i++){
	selectWindow("C"+i+1+"-Fused");
	saveAs("Tiff", fused+filenm+wavelengths[i]+"nm.tif");
	}

//apply stitch positions to flatfield corrected DAPI image
run("Grid/Collection stitching", "type=[Positions from file] order=[Defined by TileConfiguration] directory=" + outdirmaxchcorr + " layout_file=TileConfiguration.registered.clean.txt fusion_method=[Linear Blending] regression_threshold=0.30 max/avg_displacement_threshold=2.50 absolute_displacement_threshold=3.50 subpixel_accuracy computation_parameters=[Save computation time (but use more RAM)] image_output=[Fuse and display]");
setMinAndMax(0, 65535);
saveAs("Tiff", fused+filenm+stitch+"nm_corr.tif");

close("*");
run("Collect Garbage");
print(logfile, "Finished " + subdir);
print(logfile, "Finished run at:\n" + GetTimeString());
File.close(logfile);