/**
* Copyright IBM Corporation 2016
*
* Licensed under the Apache License, Version 2.0 (the "License");
* you may not use this file except in compliance with the License.
* You may obtain a copy of the License at
*
* http://www.apache.org/licenses/LICENSE-2.0
*
* Unless required by applicable law or agreed to in writing, software
* distributed under the License is distributed on an "AS IS" BASIS,
* WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
* See the License for the specific language governing permissions and
* limitations under the License.
**/

import Kitura
import SwiftMetricsKitura
import SwiftMetricsBluemix
import SwiftMetrics
import SwiftyJSON
import KituraNet
import Foundation
import CloudFoundryEnv

public class SwiftMetricsDash {

    var cpuDataStore:[JSON] = []
    var httpDataStore:[JSON] = []
    var memDataStore:[JSON] = []
    var cpuData:[CPUData] = []
    
    var monitor:SwiftMonitor
    var SM:SwiftMetrics

    public convenience init(swiftMetricsInstance : SwiftMetrics) throws {
       try self.init(swiftMetricsInstance : swiftMetricsInstance , endpoint: nil)
    }

    public init(swiftMetricsInstance : SwiftMetrics , endpoint: Router!) throws {
        // default to use passed in Router
        var create = false
        var router = Router()
        if endpoint == nil {
            create = true
        } else {
            router =  endpoint
        }
         self.SM = swiftMetricsInstance
        _ = SwiftMetricsKitura(swiftMetricsInstance: SM)
        self.monitor = SM.monitor()
        monitor.on(storeCPU)
        monitor.on(storeMem)
        monitor.on(storeHTTP)

        try startServer(createServer: create, router: router)
    }

    func startServer(createServer: Bool, router: Router) throws {
        let fm = FileManager.default
        let currentDir = fm.currentDirectoryPath
        var workingPath = ""
        if currentDir.contains(".build") {
            //we're below the Packages directory
            workingPath = currentDir
        } else {
         	//we're above the Packages directory
            workingPath = CommandLine.arguments[0]
        }
        let i = workingPath.range(of: ".build")
        var packagesPath = ""
        if i == nil {
            // we could be in bluemix
            packagesPath="/home/vcap/app/"
        } else {
            packagesPath = workingPath.substring(to: i!.lowerBound)
        }
        packagesPath.append("Packages/")
        let dirContents = try fm.contentsOfDirectory(atPath: packagesPath)
        for dir in dirContents {
            if dir.contains("SwiftMetrics") {
                packagesPath.append("\(dir)/public")
            }
        }
        router.all("/swiftdash", middleware: StaticFileServer(path: packagesPath))
        router.get("/cpuRequest", handler: getcpuRequest)
        router.get("/memRequest", handler: getmemRequest)
        router.get("/envRequest", handler: getenvRequest)
        router.get("/cpuAverages", handler: getcpuAverages)
        router.get("/httpRequest", handler: gethttpRequest)
        if createServer {
            try Kitura.addHTTPServer(onPort: CloudFoundryEnv.getAppEnv().port, with: router)
            Kitura.run()
        }
 	}

	func calculateAverageCPU() -> JSON {
		var cpuLine = JSON([])
		let tempArray = self.cpuData
		if (tempArray.count > 0) {
			var totalApplicationUse: Float = 0
			var totalSystemUse: Float = 0
			var time: Int = 0
			for cpuItem in tempArray {
				totalApplicationUse += cpuItem.percentUsedByApplication
				totalSystemUse += cpuItem.percentUsedBySystem
				time = cpuItem.timeOfSample
			}
			cpuLine = JSON([
				"time":"\(time)",
				"process":"\(totalApplicationUse/Float(tempArray.count))",
				"system":"\(totalSystemUse/Float(tempArray.count))"])
		}
		return cpuLine
	}
	

    func storeHTTP(myhttp: HTTPData) {
	let currentTime = NSDate().timeIntervalSince1970
	let tempArray = self.httpDataStore
        for httpJson in tempArray {
            if(currentTime - (Double(httpJson["time"].stringValue)! / 1000) > 1800) {
                self.httpDataStore.removeFirst()
            } else {
                break
            }
        }
        let httpLine = JSON(["time":"\(myhttp.timeOfRequest)","url":"\(myhttp.url)","duration":"\(myhttp.duration)","method":"\(myhttp.requestMethod)","statusCode":"\(myhttp.statusCode)"])
	self.httpDataStore.append(httpLine)
    }


    func storeCPU(cpu: CPUData) {
        let currentTime = NSDate().timeIntervalSince1970
        let tempArray = self.cpuDataStore
       	if tempArray.count > 0 {
       		for cpuJson in tempArray {
           		if(currentTime - (Double(cpuJson["time"].stringValue)! / 1000) > 1800) {
	                self.cpuDataStore.removeFirst()
           		} else {
                	break
	            }
        	}
       	}
       	self.cpuData.append(cpu);
    	let cpuLine = JSON(["time":"\(cpu.timeOfSample)","process":"\(cpu.percentUsedByApplication)","system":"\(cpu.percentUsedBySystem)"])
    	self.cpuDataStore.append(cpuLine)
    }

    func storeMem(mem: MemData) {
	    let currentTime = NSDate().timeIntervalSince1970
	    let tempArray = self.memDataStore
        if tempArray.count > 0 {
        	for memJson in tempArray {
            	if(currentTime - (Double(memJson["time"].stringValue)! / 1000) > 1800) {
	                self.memDataStore.removeFirst()
            	} else {
               		break
	        	}
	        }
	    }
   		let memLine = JSON([
	    	"time":"\(mem.timeOfSample)",
    		"physical":"\(mem.applicationRAMUsed)",
	    	"physical_used":"\(mem.totalRAMUsed)"
   		])
   		self.memDataStore.append(memLine)
    }

    public func getcpuRequest(request: RouterRequest, response: RouterResponse, next: @escaping () -> Void) throws {
        response.headers["Content-Type"] = "application/json"
        let tempArray = self.cpuDataStore
        if tempArray.count > 0 {
            try response.status(.OK).send(json: JSON(tempArray)).end()	        
            self.cpuDataStore.removeAll()
        } else {
    		try response.status(.OK).send(json: JSON([])).end()	        
        }
    }
    
    public func getmemRequest(request: RouterRequest, response: RouterResponse, next: @escaping () -> Void) throws {
       	response.headers["Content-Type"] = "application/json"
        let tempArray = self.memDataStore
        if tempArray.count > 0 {
		    try response.status(.OK).send(json: JSON(tempArray)).end()	        
           	self.memDataStore.removeAll()
        } else {
   			try response.status(.OK).send(json: JSON([])).end()	        
        }
    }

    public func getenvRequest(request: RouterRequest, response: RouterResponse, next: @escaping () -> Void) throws {
        response.headers["Content-Type"] = "application/json"
        var responseData: [JSON] = []
        for (param, value) in self.monitor.getEnvironmentData() {
            switch param {
                case "command.line":
                    let json: JSON = ["Parameter": "Command Line", "Value": value]
                    responseData.append(json)
                case "environment.HOSTNAME":
                    let json: JSON = ["Parameter": "Hostname", "Value": value]
                    responseData.append(json)
                case "os.arch":
                    let json: JSON = ["Parameter": "OS Architecture", "Value": value]
                    responseData.append(json)
                case "number.of.processors":
                    let json: JSON = ["Parameter": "Number of Processors", "Value": value]
                    responseData.append(json)
                default:
                    break
			}
        }
		try response.status(.OK).send(json: JSON(responseData)).end()	        
    }

	public func getcpuAverages(request: RouterRequest, response: RouterResponse, next: @escaping () -> Void) throws {
        response.headers["Content-Type"] = "application/json"
		try response.status(.OK).send(json: self.calculateAverageCPU()).end()	        
    }

	public func gethttpRequest(request: RouterRequest, response: RouterResponse, next: @escaping () -> Void) throws {
        response.headers["Content-Type"] = "application/json"
        let tempArray = self.httpDataStore
        if tempArray.count > 0 {
            try response.status(.OK).send(json: JSON(tempArray)).end()	        
          	self.httpDataStore.removeAll()
        } else {
			try response.status(.OK).send(json: JSON([])).end()	        
        }
    }
        
}
