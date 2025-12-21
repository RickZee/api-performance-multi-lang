package com.loadtest.dsql;

import com.loadtest.dsql.auth.IamTokenGenerator;

/**
 * Simple test to generate and print a DSQL IAM token for debugging.
 */
public class TestTokenGeneration {
    public static void main(String[] args) {
        String dsqlHost = System.getenv("DSQL_HOST");
        String region = System.getenv("AWS_REGION");
        String iamUsername = System.getenv("IAM_USERNAME");
        
        if (dsqlHost == null) dsqlHost = "vftmkydwxvxys6asbsc6ih2the.dsql-fnh4.us-east-1.on.aws";
        if (region == null) region = "us-east-1";
        if (iamUsername == null) iamUsername = "lambda_dsql_user";
        
        System.out.println("Generating DSQL IAM token...");
        System.out.println("Host: " + dsqlHost);
        System.out.println("Region: " + region);
        System.out.println("IAM User: " + iamUsername);
        System.out.println();
        
        IamTokenGenerator generator = new IamTokenGenerator(dsqlHost, 5432, iamUsername, region);
        try {
            String token = generator.getToken();
            System.out.println("Token generated successfully!");
            System.out.println("Token length: " + token.length());
            System.out.println("Token (first 200 chars): " + token.substring(0, Math.min(200, token.length())));
            System.out.println("Token (last 100 chars): " + token.substring(Math.max(0, token.length() - 100)));
            System.out.println();
            System.out.println("Full token:");
            System.out.println(token);
        } catch (Exception e) {
            System.err.println("Error generating token: " + e.getMessage());
            e.printStackTrace();
        } finally {
            generator.close();
        }
    }
}

