package edu.psu.cse.siis.ic3.manifest;

import java.io.File;
import java.io.FileInputStream;
import java.io.IOException;
import java.security.DigestInputStream;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;

import javax.xml.bind.DatatypeConverter;

public class SHA256Calculator {
	
	public static String getSHA256(File input) throws NoSuchAlgorithmException, IOException{
		
		byte[] buffer=new byte[8192];
		
		
		MessageDigest digest=MessageDigest.getInstance("SHA-256");
		
		DigestInputStream dis=new DigestInputStream(new FileInputStream(input),digest);
		
		while(dis.read(buffer)!=-1);
		
		
		return DatatypeConverter.printHexBinary(digest.digest());
	}
	

}
