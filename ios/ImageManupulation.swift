import Foundation
import UIKit
import Vision
import React

@objc(ImageManipulation)
class ImageManipulation: NSObject, RCTBridgeModule {
  
  static func moduleName() -> String {
    return "ImageManipulation"
  }

  @objc
  func manipulateImage(_ url: String, resolve: @escaping RCTPromiseResolveBlock, reject: @escaping RCTPromiseRejectBlock) {
    resolve("Manipulated Image URL: \(url)")
  }
  
  @objc
  func convertToGrayscale(_ imageUrl: String, resolve: @escaping RCTPromiseResolveBlock, reject: @escaping RCTPromiseRejectBlock) {
    guard let url = URL(string: imageUrl), let imageData = try? Data(contentsOf: url), let image = UIImage(data: imageData) else {
      reject("ImageError", "Invalid image URL or unable to load image", nil)
      return
    }
    
    let rect = CGRect(origin: .zero, size: image.size)
    let colorSpace = CGColorSpaceCreateDeviceGray()
    guard let context = CGContext(data: nil,
                                   width: Int(image.size.width),
                                   height: Int(image.size.height),
                                   bitsPerComponent: 8,
                                   bytesPerRow: 0,
                                   space: colorSpace,
                                   bitmapInfo: CGImageAlphaInfo.none.rawValue),
          let cgImage = image.cgImage else {
      reject("ConversionError", "Failed to create grayscale context", nil)
      return
    }
    
    context.draw(cgImage, in: rect)
    guard let grayscaleImage = context.makeImage() else {
      reject("ConversionError", "Failed to create grayscale image", nil)
      return
    }
    
    let newImage = UIImage(cgImage: grayscaleImage)
    
    if let data = newImage.jpegData(compressionQuality: 1.0) {
      let tempDir = NSTemporaryDirectory()
      let fileName = UUID().uuidString + ".jpg"
      let filePath = (tempDir as NSString).appendingPathComponent(fileName)
      let fileUrl = URL(fileURLWithPath: filePath)
      do {
        try data.write(to: fileUrl)
        resolve(fileUrl.absoluteString)
      } catch {
        reject("FileError", "Failed to save grayscale image", error)
      }
    } else {
      reject("FileError", "Failed to create image data", nil)
    }
  }
  
    // In the addLipstick function, ensure the resized image is used for Vision processing
    @objc
    func addLipstick(
        _ imageUrl: String,
        hexColor: String,
        resolve: @escaping RCTPromiseResolveBlock,
        reject: @escaping RCTPromiseRejectBlock
    ) {
        guard
            let url = URL(string: imageUrl),
            let imageData = try? Data(contentsOf: url),
            let image = UIImage(data: imageData)
        else {
            reject("ImageError", "Invalid image URL or unable to load image", nil)
            return
        }
        
        // 1) Resize the image for Vision (512x512).
        let targetSize = CGSize(width: 512, height: 512)
        guard
            let resizedImage = image.resize(to: targetSize),
            let cgImage = resizedImage.cgImage
        else {
            reject("ImageError", "Failed to resize image or create CGImage", nil)
            return
        }
        
        // 2) Precompute scale factors from the resized image back to the original
        //    so you can draw the final path on the original image.
        let widthScale  = image.size.width  / resizedImage.size.width
        let heightScale = image.size.height / resizedImage.size.height
        
        // Create a Vision request.
        let request = VNDetectFaceLandmarksRequest { request, error in
            if let error = error {
                reject("VisionError", "Error detecting face landmarks: \(error.localizedDescription)", nil)
                return
            }
            
            guard
                let results = request.results as? [VNFaceObservation],
                let face = results.first
            else {
                reject("FaceError", "No face detected", nil)
                return
            }
            
            guard
                let landmarks = face.landmarks,
                let lips = landmarks.outerLips
            else {
                reject("LandmarkError", "No lips detected", nil)
                return
            }
            
            // 3) Convert the face bounding box from normalized coords (0..1)
            //    into resized image coords (512x512).
            let boundingBox = face.boundingBox  // in normalized Vision coords
            let resizedWidth = resizedImage.size.width
            let resizedHeight = resizedImage.size.height
            
            // Vision's boundingBox origin is from bottom-left, but UIKit is top-left.
            // So we flip the y: (1 - y - height).
            let faceRectInResized = CGRect(
                x: boundingBox.origin.x * resizedWidth,
                y: (1 - boundingBox.origin.y - boundingBox.size.height) * resizedHeight,
                width: boundingBox.size.width * resizedWidth,
                height: boundingBox.size.height * resizedHeight
            )
            
            // 4) Convert each landmark point from [0..1] *within that bounding box*
            //    to the resized image space, then scale up to the original image size.
            let points = lips.normalizedPoints.map { p -> CGPoint in
                
                // Position in the resized image (512x512).
                let rx = faceRectInResized.origin.x + (p.x * faceRectInResized.size.width)
                let ry = faceRectInResized.origin.y + ((1 - p.y) * faceRectInResized.size.height)
                
                // Now scale up to the original image’s coordinate space.
                let originalX = rx * widthScale
                let originalY = ry * heightScale
                
                return CGPoint(x: originalX, y: originalY)
            }
            
            // 5) Build a path from these points.
            let path = UIBezierPath()
            if let firstPoint = points.first {
                path.move(to: firstPoint)
                for point in points.dropFirst() {
                    path.addLine(to: point)
                }
                path.close()
            }
            
            // 6) Draw onto the original image (full size).
            UIGraphicsBeginImageContextWithOptions(image.size, false, image.scale)
            guard let context = UIGraphicsGetCurrentContext() else {
                reject("DrawingError", "Failed to create graphics context", nil)
                return
            }
            
            // Draw the original image as background.
            image.draw(at: .zero)
            
            // Add the lips path and fill with the chosen color + alpha.
            context.addPath(path.cgPath)
            context.setFillColor(UIColor(hex: hexColor).cgColor)
            context.setAlpha(0.7)
            context.fillPath()
            
            // Grab the new image from the context.
            guard let newImage = UIGraphicsGetImageFromCurrentImageContext() else {
                reject("DrawingError", "Failed to create new image", nil)
                return
            }
            UIGraphicsEndImageContext()
            
            // 7) Save the new image to a temporary file.
            if let data = newImage.jpegData(compressionQuality: 1.0) {
                let fileName = UUID().uuidString + ".jpg"
                let fileUrl = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(fileName)
                do {
                    try data.write(to: fileUrl)
                    resolve(fileUrl.absoluteString)
                } catch {
                    reject("FileError", "Failed to save image", error)
                }
            } else {
                reject("FileError", "Failed to create image data", nil)
            }
        }
        
        // Perform the request in a background queue.
        DispatchQueue.global(qos: .userInitiated).async {
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                DispatchQueue.main.async {
                    reject("VisionError", "Vision request failed: \(error.localizedDescription)", nil)
                }
            }
        }
    }


    @objc
func changeEyebrowColor(
    _ imageUrl: String,
    hexColor: String,
    resolve: @escaping RCTPromiseResolveBlock,
    reject: @escaping RCTPromiseRejectBlock
) {
    guard
        let url = URL(string: imageUrl),
        let imageData = try? Data(contentsOf: url),
        let image = UIImage(data: imageData)
    else {
        reject("ImageError", "Invalid image URL or unable to load image", nil)
        return
    }
    
    // Resize image for Vision processing
    let targetSize = CGSize(width: 512, height: 512)
    guard
        let resizedImage = image.resize(to: targetSize),
        let cgImage = resizedImage.cgImage
    else {
        reject("ImageError", "Failed to resize image or create CGImage", nil)
        return
    }
    
    let widthScale = image.size.width / resizedImage.size.width
    let heightScale = image.size.height / resizedImage.size.height
    
    let request = VNDetectFaceLandmarksRequest { request, error in
        if let error = error {
            reject("VisionError", "Face detection failed: \(error.localizedDescription)", nil)
            return
        }
        
        guard
            let results = request.results as? [VNFaceObservation],
            let face = results.first
        else {
            reject("FaceError", "No face detected", nil)
            return
        }
        
        // Get eyebrow landmarks
        guard
            let landmarks = face.landmarks,
            let leftEyebrow = landmarks.leftEyebrow,
            let rightEyebrow = landmarks.rightEyebrow
        else {
            reject("LandmarkError", "Eyebrows not detected", nil)
            return
        }
        
        // Process both eyebrows
        let leftPoints = self.convertLandmarks(
            points: leftEyebrow.normalizedPoints,
            faceBoundingBox: face.boundingBox,
            resizedImageSize: resizedImage.size,
            widthScale: widthScale,
            heightScale: heightScale
        )
        
        let rightPoints = self.convertLandmarks(
            points: rightEyebrow.normalizedPoints,
            faceBoundingBox: face.boundingBox,
            resizedImageSize: resizedImage.size,
            widthScale: widthScale,
            heightScale: heightScale
        )
        
        // Draw eyebrows
        UIGraphicsBeginImageContextWithOptions(image.size, false, image.scale)
        guard let context = UIGraphicsGetCurrentContext() else {
            reject("DrawingError", "Failed to create graphics context", nil)
            return
        }
        
        image.draw(at: .zero)
        self.drawEyebrow(context: context, points: leftPoints, color: hexColor)
        self.drawEyebrow(context: context, points: rightPoints, color: hexColor)
        
        guard let newImage = UIGraphicsGetImageFromCurrentImageContext() else {
            reject("DrawingError", "Failed to create new image", nil)
            return
        }
        UIGraphicsEndImageContext()
        
        // Save image
        if let data = newImage.jpegData(compressionQuality: 1.0) {
            let fileName = UUID().uuidString + ".jpg"
            let fileUrl = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(fileName)
            do {
                try data.write(to: fileUrl)
                resolve(fileUrl.absoluteString)
            } catch {
                reject("FileError", "Failed to save image", error)
            }
        } else {
            reject("FileError", "Failed to create image data", nil)
        }
    }
    
    DispatchQueue.global(qos: .userInitiated).async {
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
        } catch {
            DispatchQueue.main.async {
                reject("VisionError", "Vision request failed: \(error.localizedDescription)", nil)
            }
        }
    }
}

// MARK: - Helper Methods
private func convertLandmarks(
    points: [CGPoint],
    faceBoundingBox: CGRect,
    resizedImageSize: CGSize,
    widthScale: CGFloat,
    heightScale: CGFloat
) -> [CGPoint] {
    return points.map { normalizedPoint in
        // Convert to resized image coordinates
        let x = faceBoundingBox.origin.x * resizedImageSize.width + 
               normalizedPoint.x * faceBoundingBox.width * resizedImageSize.width
        let y = (1 - faceBoundingBox.origin.y - faceBoundingBox.height) * resizedImageSize.height + 
               (1 - normalizedPoint.y) * faceBoundingBox.height * resizedImageSize.height
        
        // Scale to original image coordinates
        return CGPoint(
            x: x * widthScale,
            y: y * heightScale
        )
    }
}

private func drawEyebrow(
    context: CGContext,
    points: [CGPoint],
    color: String
) {
    guard points.count >= 2 else { return }
    
    let path = UIBezierPath()
    path.move(to: points[0])
    
    // Pürüzsüz bir eğri oluşturmak için quadCurve kullanımı (isteğe göre):
    for i in 1..<points.count {
        let prev = points[i - 1]
        let curr = points[i]
        let mid = CGPoint(x: (prev.x + curr.x)/2.0, y: (prev.y + curr.y)/2.0)
        path.addQuadCurve(to: mid, controlPoint: prev)
    }
    
    // İsterseniz patikayı kapatın (örnek):
    // path.addLine(to: points[0])
    // path.close()
    
    context.setFillColor(UIColor(hex: color).cgColor)
    context.setAlpha(0.7)        // Biraz şeffaflık isterseniz
    context.addPath(path.cgPath)
    context.fillPath()           // stroke yerine fill
}



}

// Helper extension to create UIColor from hex
extension UIColor {
  convenience init(hex: String) {
    var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
    hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

    var rgb: UInt64 = 0
    Scanner(string: hexSanitized).scanHexInt64(&rgb)

    let red = CGFloat((rgb & 0xFF0000) >> 16) / 255.0
    let green = CGFloat((rgb & 0x00FF00) >> 8) / 255.0
    let blue = CGFloat(rgb & 0x0000FF) / 255.0

    self.init(red: red, green: green, blue: blue, alpha: 1.0)
  }
}


// Update the UIImage extension to resize while maintaining aspect ratio
extension UIImage {
    func resize(to targetSize: CGSize) -> UIImage? {
        let size = self.size
        let widthRatio = targetSize.width / size.width
        let heightRatio = targetSize.height / size.height
        let scale = min(widthRatio, heightRatio)
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let rect = CGRect(origin: .zero, size: newSize)
        UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
        self.draw(in: rect)
        let resizedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return resizedImage
    }
}
