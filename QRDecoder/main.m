//
//  main.m
//  QRDecoder
//
//  Created by KikuraYuichiro on 2014/09/14.
//  Copyright (c) 2014年 KikuraYuichiro. All rights reserved.
//

#include <Cocoa/Cocoa.h>
#include <math.h>

#define EPS 0.3

void save(NSData *data, NSString *path);
NSBitmapImageRep* convertToImageRep(NSImage *image);
Boolean* monochrome(NSBitmapImageRep *imageRep, const int width, const int height);
void detectFinderPattern(Boolean *monochro, const int width, const int height);

//for DEBUG
NSBitmapImageRep *imageRep;

typedef struct {
	int cx;
	int cy;
	int size;
} FinderPattern;

int main(void)
{
	NSOpenPanel *openPanel = [NSOpenPanel openPanel];
	openPanel.allowedFileTypes = @[@"png", @"jpg", @"jpeg"];
	
	if ([openPanel runModal] != NSOKButton) {
		NSLog(@"Canceled.");
		exit(0);
	}
	
	NSImage *inputImage = [[NSImage alloc] initWithContentsOfURL:openPanel.URL];
	
	//1. ファイルをimageRepデータに変換
	imageRep = convertToImageRep(inputImage);
	const int width = (int)imageRep.pixelsWide;
	const int height = (int)imageRep.pixelsHigh;

	//2. 2値化
	Boolean *data = monochrome(imageRep, width, height);
	
	//3. マーク検出
	detectFinderPattern(data, width, height);
	
	NSData *output = [imageRep representationUsingType:NSBMPFileType properties:nil];
	save(output, [openPanel.URL.path stringByAppendingString:@"_out.bmp"]);
	
    return 0;
}

void save(NSData *data, NSString *path)
{
	[data writeToFile:path atomically:NO];
}

NSBitmapImageRep* convertToImageRep(NSImage *image)
{
	NSData *tiffData = [image TIFFRepresentation];
	NSBitmapImageRep *imageRep = [NSBitmapImageRep imageRepWithData:tiffData];
	
	return imageRep;
}

int detectThreshold(int arr[], const int ARR_SIZE)
{
	//大津のアルゴリズム
	float maxSigma = 0, maxSigmaIndex = 0;
	float sigma;
	int n1 = 0, n2 = 0, s1 = 0, s2 = 0;
	
	//n:画素数 s:画素値の合計
	
	for (int i = 0; i < ARR_SIZE; i++) {
		n2 += arr[i];
		s2 += arr[i]*i;
	}

	for (int i = 0; i < ARR_SIZE; i++) {
		sigma = 1.0 * n1 * n2 * pow(1.0*s1/n1-1.0*s2/n2, 2) / pow(n1+n2, 2);

		if (sigma > maxSigma) {
			maxSigma = sigma;
			maxSigmaIndex = i;
		}
		
		n1 += arr[i];
		n2 -= arr[i];
		s1 += arr[i] * i;
		s2 -= arr[i] * i;
	}
	
	return maxSigmaIndex;
}

Boolean* monochrome(NSBitmapImageRep *imageRep, const int width, const int height)
{
	Boolean *data = malloc(sizeof(Boolean) * width * height);
	NSUInteger *val = malloc(sizeof(NSUInteger) * 3);
	int arrBrightness[32];//幅8で32段階
	
	for (int i = 0; i < 32; i++) arrBrightness[i] = 0;
	
	for (int y = 0; y < height; y++) {
		for (int x = 0; x < width; x++) {
			[imageRep getPixel:val atX:x y:y];
			arrBrightness[(val[0]+val[1]+val[2])/3/8]++;
		}
	}
	int threshold = detectThreshold(arrBrightness, 32);
	
	for (int y = 0; y < height; y++) {
		for (int x = 0; x < width; x++) {
			[imageRep getPixel:val atX:x y:y];
			data[y*width+x] = (val[0]+val[1]+val[2])/3 < threshold*8;
		}
	}
	
	return data;
}

void detectFinderPattern(Boolean *monochro, const int width, const int height)
{
	const int MIN_SIZE = MIN(width, height)/30;
	NSUInteger blue[3] = {0, 0, 255};
	int markWidth[5] = {0, 0, 0, 0, 0};
	int dx = 0;
	float rate;
	Boolean mode;
	Boolean flagClear;
	
	NSMutableArray *points = [NSMutableArray array];
	//まず、横に走査しながら候補を探す
	for (int y = 0; y < height; y++) {
		for (int x = 0; x < width; x++) {
			
			if (!monochro[y*width+x]) continue;
			
			dx = 1;
			mode = true;
			for (int i = 0; i < 5; i++) {
				markWidth[i] = 0;
				while (monochro[y*width+x+dx] == mode && x+dx < width) {
					dx++;
					markWidth[i]++;
				}
				if (x+dx >= width) break;
				
				mode = !mode;
			}
			if (x+dx >= width) break;
			
			if (markWidth[2] >= MIN_SIZE) {
				flagClear = true;
				for (int i = 0; i < 5; i++) {
					if (i == 2) continue;
					
					rate = 1.0*markWidth[i]*3/markWidth[2];
					flagClear &= (rate > 1.0-EPS & rate < 1.0+EPS);
					if (!flagClear) break;
				}
				
				if (flagClear) {
					int size = markWidth[0]+markWidth[1]+markWidth[2]+markWidth[3]+markWidth[4];

					FinderPattern fp = {
						.cx = x+size/2,
						.cy = y,
						.size = size
					};
					[points addObject:[NSData dataWithBytes:&fp length:sizeof(FinderPattern)]];
				}
			}
			
			x += markWidth[0]+markWidth[1] - 1;
		}
	}
	
	//次に、縦に走査して、パターンの中央を探す
	for (int i = 0; i < points.count; i++) {
		FinderPattern fp;
		[(NSData *)points[i] getBytes:&fp length:sizeof(FinderPattern)];

		int x = fp.cx, y = fp.cy-fp.size/2;
		int dy = 0;
		mode = true;
		for (int i = 0; i < 5; i++) {
			markWidth[i] = 0;
			while (monochro[(y+dy)*width+x] == mode && y+dy < height) {
				dy++;
				markWidth[i]++;
			}
			if (y+dy >= height) break;
			
			mode = !mode;
		}
		if (y+dy >= height) break;
		
		if (markWidth[2] >= MIN_SIZE) {
			flagClear = true;
			for (int i = 0; i < 5; i++) {
				if (i == 2) continue;
				
				rate = 1.0*markWidth[i]*3/markWidth[2];
				flagClear &= (rate > 1.0-EPS & rate < 1.0+EPS);
				if (!flagClear) break;
			}
			
			if (flagClear) {
				int x1 = fp.cx-fp.size/2, x2 = fp.cx+fp.size/2;
				int y1 = fp.cy-fp.size/2, y2 = fp.cy+fp.size/2;
				
				for (int d = 0; d < fp.size; d++) {
					[imageRep setPixel:blue atX:x1+d y:y1];
					[imageRep setPixel:blue atX:x1+d y:y2];
					[imageRep setPixel:blue atX:x1 y:y1+d];
					[imageRep setPixel:blue atX:x2 y:y1+d];
				}
			}
		}
	}
}