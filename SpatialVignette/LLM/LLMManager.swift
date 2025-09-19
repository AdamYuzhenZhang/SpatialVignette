//
//  LLMManager.swift
//  SpatialVignette
//
//  Created by Yuzhen Zhang on 9/16/25.
//

import OpenAI
import UIKit
import MobileCoreServices

/// A shared singleton class to manage interactions with the OpenAI API.
public final class LLMManager {
    /// The shared instance for easy access throughout the app.
    public static let shared = LLMManager()
    
    private var openAI = OpenAI(apiToken: "")
    
    /*
    /// Analyzes a cropped subject image within the context of the original full image.
    public func identifyAndDescribe(subjectImage: CGImage, originalImage: CGImage) async -> String? {
            guard let subjectImageAsBase64 = subjectImage.toBase64(),
                  let originalImageAsBase64 = originalImage.toBase64() else {
                print("Error converting images to base64")
                return nil
            }
        
        let query = ChatQuery(
                messages: [
                    .user([
                        .text("Identify the main object in this image and provide a concise one-sentence description."),
                        .imageUrl(.init(url: "data:image/jpeg;base64,\(subjectImageAsBase64)")!)
                    ])
                ],
                model: .gpt4_o // Use a vision-capable model
            )

            // 4. Construct the chat query
            let query = ChatQuery(
                messages: [
                    .user(
                        .init(
                            content: .parts([
                                                    .text("Please identify the object in the first image (the cropped subject) and provide a concise description. The second image is the original, full-frame image for context."),
                                                    .imageUrl(.init(url: "data:image/jpeg;base64,\(subjectImageAsBase64)")),
                                                    .imageUrl(.init(url: "data:image/jpeg;base64,\(originalImageAsBase64)"))
                                                ])
                        )
                    )
                ],
                model: .gpt4_o
            )

            // 5. Make the API call and handle the response
            do {
                let result = try await openAI.chats(query: query)
                return result.choices.first?.message.content?.string
            } catch {
                print("Error: \(error)")
                return nil
            }
    }
    */
}


