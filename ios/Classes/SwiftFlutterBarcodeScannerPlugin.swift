import Flutter
import UIKit

enum ScanMode:Int{
    case QR
    case BARCODE
    case DEFAULT
    
    var index: Int {
        return rawValue
    }
}

public class SwiftFlutterBarcodeScannerPlugin: NSObject, FlutterPlugin, ScanBarcodeDelegate,FlutterStreamHandler {
    
    public static var viewController = UIViewController()
    public static var lineColor:String=""
    public static var cancelButtonText:String=""
    public static var isShowFlashIcon:Bool=false
    var pendingResult:FlutterResult!
    public static var isContinuousScan:Bool=false
    static var barcodeStream:FlutterEventSink?=nil
    public static var scanMode = ScanMode.QR.index
    
    public static func register(with registrar: FlutterPluginRegistrar) {
        viewController = (UIApplication.shared.delegate?.window??.rootViewController)!
        let channel = FlutterMethodChannel(name: "flutter_barcode_scanner", binaryMessenger: registrar.messenger())
        let instance = SwiftFlutterBarcodeScannerPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
        let eventChannel=FlutterEventChannel(name: "flutter_barcode_scanner_receiver", binaryMessenger: registrar.messenger())
        eventChannel.setStreamHandler(instance)
    }
    
    /// Check for camera availability
    func checkCameraAvailability()->Bool{
        return true
    }
    
    func checkForCameraPermission()->Bool{
        return true
    }
    
    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        SwiftFlutterBarcodeScannerPlugin.barcodeStream = events
        return nil
    }
    
    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        SwiftFlutterBarcodeScannerPlugin.barcodeStream=nil
        return nil
    }
    
    public static func onBarcodeScanReceiver( barcode:String){
        barcodeStream!(barcode)
    }
    
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let args:Dictionary<String, AnyObject> = call.arguments as! Dictionary<String, AnyObject>;
        if let colorCode = args["lineColor"] as? String{
            SwiftFlutterBarcodeScannerPlugin.lineColor = colorCode
        }else {
            SwiftFlutterBarcodeScannerPlugin.lineColor = "#ff6666"
        }
        if let buttonText = args["cancelButtonText"] as? String{
            SwiftFlutterBarcodeScannerPlugin.cancelButtonText = buttonText
        }else {
            SwiftFlutterBarcodeScannerPlugin.cancelButtonText = "Cancel"
        }
        if let flashStatus = args["isShowFlashIcon"] as? Bool{
            SwiftFlutterBarcodeScannerPlugin.isShowFlashIcon = flashStatus
        }else {
            SwiftFlutterBarcodeScannerPlugin.isShowFlashIcon = false
        }
        if let isContinuousScan = args["isContinuousScan"] as? Bool{
            SwiftFlutterBarcodeScannerPlugin.isContinuousScan = isContinuousScan
        }else {
            SwiftFlutterBarcodeScannerPlugin.isContinuousScan = false
        }
        
        if let scanModeReceived = args["scanMode"] as? Int {
            if scanModeReceived == ScanMode.DEFAULT.index {
                SwiftFlutterBarcodeScannerPlugin.scanMode = ScanMode.QR.index
            }else{
                SwiftFlutterBarcodeScannerPlugin.scanMode = scanModeReceived
            }
        }else{
            SwiftFlutterBarcodeScannerPlugin.scanMode = ScanMode.QR.index
        }
        
        pendingResult=result
        let controller = BarcodeScannerViewController()
        controller.delegate = self
        
        if #available(iOS 13.0, *) {
            controller.modalPresentationStyle = .fullScreen
        }
        
        SwiftFlutterBarcodeScannerPlugin.viewController.present(controller
        , animated: true) {
            
        }
    }
    
    public func userDidScanWith(barcode: String){
        pendingResult(barcode)
    }
    
    /// Show common alert dialog
    func showAlertDialog(title:String,message:String){
        let alertController = UIAlertController(title: title, message: message, preferredStyle: .alert)
        let alertAction = UIAlertAction(title: "Ok", style: .default, handler: nil)
        alertController.addAction(alertAction)
        SwiftFlutterBarcodeScannerPlugin.viewController.present(alertController, animated: true, completion: nil)
    }
}

protocol ScanBarcodeDelegate {
    func userDidScanWith(barcode: String)
}

class BarcodeScannerViewController: UIViewController {
    public var delegate: ScanBarcodeDelegate? = nil
    private var qrCodeFrameView: UIView?
    private var scanlineRect = CGRect.zero
    private var scanlineStartY: CGFloat = 0
    private var scanlineStopY: CGFloat = 0
    private var topBottomMargin: CGFloat = 80
    private var scanLine: UIView = UIView()
    var screenSize = UIScreen.main.bounds
    private var isOrientationPortrait = true
    var screenHeight:CGFloat = 0

    private lazy var resourceBundle: Bundle = {
        let myBundle = Bundle(for: BarcodeScannerViewController.self)

        guard let resourceBundleURL = myBundle.url(
            forResource: "FlutterBarcodeScanner", withExtension: "bundle")
            else { fatalError("FlutterBarcodeScanner.bundle not found!") }

        guard let resourceBundle = Bundle(url: resourceBundleURL)
            else { fatalError("Cannot access FlutterBarcodeScanner.bundle!") }

        return resourceBundle
    }()
    
    private lazy var xCor: CGFloat! = {
        return self.isOrientationPortrait ? (screenSize.width - (screenSize.width*0.8))/2 :
            (screenSize.width - (screenSize.width*0.6))/2
    }()
    private lazy var yCor: CGFloat! = {    
        return self.isOrientationPortrait ? (screenSize.height - (screenSize.width*0.8))/2 :
            (screenSize.height - (screenSize.height*0.8))/2
    }()
    //Bottom view
    private lazy var bottomView : UIView! = {
        let view = UIView()
        view.backgroundColor = UIColor.black
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    /// Create and return flash button
    private lazy var flashIcon : UIButton! = {
        let flashButton = UIButton()
        flashButton.translatesAutoresizingMaskIntoConstraints=false
        
        flashButton.setImage(UIImage(named: "ic_flash_off.png", in: resourceBundle, compatibleWith: nil),for:.normal)
        
        flashButton.addTarget(self, action: #selector(BarcodeScannerViewController.flashButtonClicked), for: .touchUpInside)
        return flashButton
    }()
    
    
    /// Create and return cancel button
    public lazy var cancelButton: UIButton! = {
        let view = UIButton()
        view.setTitle(SwiftFlutterBarcodeScannerPlugin.cancelButtonText, for: .normal)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.addTarget(self, action: #selector(BarcodeScannerViewController.cancelButtonClicked), for: .touchUpInside)
        return view
    }()
    
    override public func viewDidLoad() {
        super.viewDidLoad()
        self.isOrientationPortrait = isLandscape
        self.initUIComponents()
    }
    
    override public func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        self.moveVertically()
    }
    
    // Init UI components needed
    func initUIComponents(){
        if isOrientationPortrait {
            screenHeight = (CGFloat)((SwiftFlutterBarcodeScannerPlugin.scanMode == ScanMode.QR.index) ? (screenSize.width * 0.8) : (screenSize.width * 0.5))
            
        } else {
            screenHeight = (CGFloat)((SwiftFlutterBarcodeScannerPlugin.scanMode == ScanMode.QR.index) ? (screenSize.height * 0.6) : (screenSize.height * 0.5))
        }
    }
    
    func drawUIOverlays(withCompletion processCompletionCallback: () -> Void){
        //    func drawUIOverlays(){
        let overlayPath = UIBezierPath(rect: view.bounds)
        
        let transparentPath = UIBezierPath(rect: CGRect(x: xCor, y: yCor, width: self.isOrientationPortrait ? (screenSize.width*0.8) : (screenSize.height*0.8), height: screenHeight))

        overlayPath.append(transparentPath)
        overlayPath.usesEvenOddFillRule = true
        let fillLayer = CAShapeLayer()
        
        fillLayer.path = overlayPath.cgPath
        fillLayer.fillRule = CAShapeLayerFillRule.evenOdd
        fillLayer.fillColor = UIColor(red: 0, green: 0, blue: 0, alpha: 0.5).cgColor
    
        
        let scanRect = CGRect(x: xCor, y: yCor, width: self.isOrientationPortrait ? (screenSize.width*0.8) : (screenSize.height*0.8), height: screenHeight)
        
        // Initialize QR Code Frame to highlight the QR code
        qrCodeFrameView = UIView()
        
        qrCodeFrameView!.frame = CGRect(x: 0, y: 0, width: self.isOrientationPortrait ? (screenSize.width * 0.8) : (screenSize.height * 0.8), height: screenHeight)
        
        
        if let qrCodeFrameView = qrCodeFrameView {
            self.view.addSubview(qrCodeFrameView)
            self.view.bringSubviewToFront(qrCodeFrameView)
            self.view.bringSubviewToFront(bottomView)
            self.view.bringSubviewToFront(flashIcon)
            if(!SwiftFlutterBarcodeScannerPlugin.isShowFlashIcon){
                flashIcon.isHidden=true
            }
            qrCodeFrameView.layoutIfNeeded()
            qrCodeFrameView.layoutSubviews()
            qrCodeFrameView.setNeedsUpdateConstraints()
            self.view.bringSubviewToFront(cancelButton)
        }
        setConstraintsForControls()
        self.drawLine()
        processCompletionCallback()
    }
    
    /// Apply constraints to ui components
    private func setConstraintsForControls() {
        self.view.addSubview(bottomView)
        self.view.addSubview(cancelButton)
        self.view.addSubview(flashIcon)
        
        bottomView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant:0).isActive = true
        bottomView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant:0).isActive = true
        bottomView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant:0).isActive = true
        bottomView.heightAnchor.constraint(equalToConstant:self.isOrientationPortrait ? 100.0 : 70.0).isActive=true
        
        flashIcon.centerXAnchor.constraint(equalTo: view.centerXAnchor).isActive = true
        flashIcon.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -10).isActive = true
        flashIcon.heightAnchor.constraint(equalToConstant: 40.0).isActive = true
        flashIcon.widthAnchor.constraint(equalToConstant: 40.0).isActive = true
        
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        cancelButton.widthAnchor.constraint(equalToConstant: 100.0).isActive = true
        cancelButton.heightAnchor.constraint(equalToConstant: 70.0).isActive = true
        cancelButton.bottomAnchor.constraint(equalTo:view.bottomAnchor,constant: 0).isActive=true
        cancelButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant:10).isActive = true
    }
    
    /// Flash button click event listener
    @IBAction private func flashButtonClicked() {
        if #available(iOS 10.0, *) {
            if flashIcon.image(for: .normal) == UIImage(named: "ic_flash_off.png", in: resourceBundle, compatibleWith: nil){
                flashIcon.setImage(UIImage(named: "ic_flash_on.png", in: resourceBundle, compatibleWith: nil),for:.normal)
            }else{
                flashIcon.setImage(UIImage(named: "ic_flash_off.png", in: resourceBundle, compatibleWith: nil),for:.normal)
            }
        } else {
            /// Handle further checks
        }
    }
    
    
    /// Cancel button click event listener
    @IBAction private func cancelButtonClicked() {
        if SwiftFlutterBarcodeScannerPlugin.isContinuousScan{
            self.dismiss(animated: true, completion: {
                SwiftFlutterBarcodeScannerPlugin.onBarcodeScanReceiver(barcode: "-1")
            })
        }else{
            if self.delegate != nil {
                self.dismiss(animated: true, completion: {
                    self.delegate?.userDidScanWith(barcode: "-1")
                })
            }
        }
    }
    
    /// Draw scan line
    private func drawLine() {
        self.view.addSubview(scanLine)
        scanLine.backgroundColor = hexStringToUIColor(hex: SwiftFlutterBarcodeScannerPlugin.lineColor)
        scanlineRect = CGRect(x: xCor, y: yCor, width:self.isOrientationPortrait ? (screenSize.width*0.8) : (screenSize.height*0.8), height: 2)
      
        scanlineStartY = yCor
        
        var stopY:CGFloat
        
        if SwiftFlutterBarcodeScannerPlugin.scanMode == ScanMode.QR.index {
            let w = self.isOrientationPortrait ? (screenSize.width*0.8) : (screenSize.height*0.6)
            stopY = (yCor + w)
        } else {
            let w = self.isOrientationPortrait ? (screenSize.width * 0.5) : (screenSize.height * 0.5)
            stopY = (yCor + w)
        }
        scanlineStopY = stopY
    }
    
    /// Animate scan line vertically
    private func moveVertically() {
        scanLine.frame  = scanlineRect
        scanLine.center = CGPoint(x: scanLine.center.x, y: scanlineStartY)
        scanLine.isHidden = false
        weak var weakSelf = scanLine
        UIView.animate(withDuration: 2.0, delay: 0.0, options: [.repeat, .autoreverse, .beginFromCurrentState], animations: {() -> Void in
            weakSelf!.center = CGPoint(x: weakSelf!.center.x, y: self.scanlineStopY)
        }, completion: nil)
    }
    
    var isLandscape: Bool {
        return UIDevice.current.orientation.isValidInterfaceOrientation
            ? UIDevice.current.orientation.isPortrait
            : UIApplication.shared.statusBarOrientation.isPortrait
    }

    private func launchApp(decodedURL: String) {
        if presentedViewController != nil {
            return
        }
        if self.delegate != nil {
            self.dismiss(animated: true, completion: {
                self.delegate?.userDidScanWith(barcode: decodedURL)
            })
        }
    }
}

/// Convert hex string to UIColor
func hexStringToUIColor (hex:String) -> UIColor {
    var cString:String = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    
    if (cString.hasPrefix("#")) {
        cString.remove(at: cString.startIndex)
    }
    
    if ((cString.count) != 6 && (cString.count) != 8) {
        return UIColor.gray
    }
    
    var rgbaValue:UInt32 = 0
    
    if (!Scanner(string: cString).scanHexInt32(&rgbaValue)) {
        return UIColor.gray
    }
    
    var aValue:CGFloat = 1.0
    if ((cString.count) == 8) {
        aValue = CGFloat((rgbaValue & 0xFF000000) >> 24) / 255.0
    }
    
    let rValue:CGFloat = CGFloat((rgbaValue & 0x00FF0000) >> 16) / 255.0
    let gValue:CGFloat = CGFloat((rgbaValue & 0x0000FF00) >> 8) / 255.0
    let bValue:CGFloat = CGFloat(rgbaValue & 0x000000FF) / 255.0
    
    return UIColor(
        red: rValue,
        green: gValue,
        blue: bValue,
        alpha: aValue
    )
}
