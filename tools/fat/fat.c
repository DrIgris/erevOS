#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

typedef uint8_t bool;
#define true 1
#define false 0
//FNAME is the file name size in Dir Entry Specification, similar for FEXT = File Ext
#define FNAME_SIZE 8
#define FEXT_SIZE 3

typedef struct {
	uint8_t BootJumpInstruction[3];
	uint8_t OemIdentifier[8];
	uint16_t BytesPerSector;
	uint8_t SectorsPerCluster;
	uint16_t ReservedSectors;
	uint8_t FatCount;
	uint16_t DirEntryCount;
	uint16_t TotalSectors;
	uint8_t MediaDescriptionType;
	uint16_t SectorsPerFat;
	uint16_t SectorsPerTrack;
	uint16_t Heads;
	uint32_t HiddenSectors;
	uint32_t LargeSectorCount;

	uint8_t DriveNumber;
	uint8_t _Reserved;
	uint8_t Signature;
	uint32_t VolumeId;
	uint8_t VolumeLabel[11];
	uint8_t SystemId[8];
} __attribute__((packed)) BootSector;

typedef struct {
	uint8_t name[8];
	uint8_t ext[3];
	uint8_t attr;
	uint8_t __reserved;
	uint8_t CreateTimeFine;
	uint16_t CreationTime;
	uint16_t CreationDate;
	uint16_t LastAccess;
	uint16_t EAIndex;
	uint16_t LastModTime;
	uint16_t LastModDate;
	uint16_t FirstCluster;
	uint32_t FileSize;
} __attribute__((packed)) DirectoryEntry;

BootSector g_BS;
uint8_t* g_FAT = NULL;
DirectoryEntry* g_RootDir = NULL;

bool readBootSector(FILE* disk) {
	return fread(&g_BS, sizeof(g_BS), 1, disk) > 0;
}

bool readSectors(FILE* disk, uint32_t lba, uint32_t count, void* bufferOut) {
	bool ok = true;
	ok = ok && (fseek(disk, lba * g_BS.BytesPerSector, SEEK_SET) == 0);
	ok = ok && (fread(bufferOut, g_BS.BytesPerSector, count, disk) == count);
	return ok;
}

bool readFAT(FILE* disk) {
	g_FAT = (uint8_t*) malloc(g_BS.SectorsPerFat * g_BS.BytesPerSector);
	return readSectors(disk, g_BS.ReservedSectors, g_BS.SectorsPerFat, g_FAT);
}

bool readRootDirectory(FILE* disk) {
	uint32_t lba = g_BS.ReservedSectors + g_BS.SectorsPerFat * g_BS.FatCount;
	uint32_t size = sizeof(DirectoryEntry)*g_BS.DirEntryCount;
	uint32_t sectors = (size / g_BS.BytesPerSector);
	if(size % g_BS.BytesPerSector > 0) {
		sectors++;
	}
	g_RootDir = (DirectoryEntry*) malloc(sectors * g_BS.BytesPerSector);
	return readSectors(disk, lba, sectors, g_RootDir);
}

DirectoryEntry* findFile(const char* name) {
	for(uint32_t i = 0; i < g_BS.DirEntryCount; i++) {
		if(memcmp(name, g_RootDir[i].name, 11) == 0) {
			return &g_RootDir[i];
		}
	}
	return NULL;
}

int main (int argc, char** argv) {
	if (argc < 3) {
		printf("Syntax: %s <disk image> <file name>\n", argv[0]);
		return -1;
	}

	FILE* disk = fopen(argv[1], "rb");
	if(!disk) {
		fprintf(stderr, "Cannot Open Disk Image %s", argv[1]);
		return -1;
	}
	if(!readBootSector(disk)){
		fprintf(stderr, "Could not read boot sector\n");
		return -2;
	}
	if(!readFAT(disk)) {
		fprintf(stderr, "Could not read FAT\n");
		free(g_FAT);
		return -3;
	}
	if(!readRootDirectory(disk)) {
		fprintf(stderr, "Error Reading Root Dir\n");
		free(g_FAT);
		free(g_RootDir);
		return -4;
	}
	DirectoryEntry* fileEntry = findFile(argv[2]);
	if(!fileEntry) {
		fprintf(stderr, "Could not find file %s\n", argv[2]);
		free(g_FAT);
		free(g_RootDir);
		return -5;
	}
	free(g_FAT);
	free(g_RootDir);
	return 0;
}
