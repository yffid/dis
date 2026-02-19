package display.hermosaapp.com

import android.os.Bundle
import android.util.Log
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.*
import java.util.Locale
import java.util.UUID

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.hermosaapp.nearpay"
    private val mainScope = CoroutineScope(Dispatchers.Main + Job())
    private var nearPay: Any? = null

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler {
            call, result -> handleMethodCall(call, result)
        }
    }

    private fun handleMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "initialize" -> initializeNearPay(call, result)
            "jwtLogin" -> jwtLogin(call, result)
            "purchase" -> processPurchase(call, result)
            "checkPermissions" -> checkPermissions(result)
            "isNfcEnabled" -> isNfcEnabled(result)
            else -> result.notImplemented()
        }
    }

    private fun initializeNearPay(call: MethodCall, result: MethodChannel.Result) {
        try {
            val environmentStr = call.argument<String>("environment") ?: "sandbox"
            
            // Using reflection to find the correct Environment and Builder
            val environmentClass = try {
                Class.forName("io.nearpay.sdk.utils.enums.Environment")
            } catch (e: Exception) {
                Class.forName("io.nearpay.terminalsdk.data.models.Environment")
            }
            
            val environmentValue = if (environmentStr == "sandbox") {
                environmentClass.getField("SANDBOX").get(null)
            } else {
                environmentClass.getField("PRODUCTION").get(null)
            }

            val nearPayClass = try {
                Class.forName("io.nearpay.sdk.NearPay")
            } catch (e: Exception) {
                Class.forName("io.nearpay.terminalsdk.TerminalSDK")
            }

            val builderClass = nearPayClass.classes.find { it.simpleName == "Builder" }
                ?: Class.forName("${nearPayClass.name}\$Builder")
            
            val builder = builderClass.getConstructor(android.content.Context::class.java).newInstance(this)
            
            builderClass.getMethod("environment", environmentClass).invoke(builder, environmentValue)
            builderClass.getMethod("locale", Locale::class.java).invoke(builder, Locale.getDefault())
            
            nearPay = builderClass.getMethod("build").invoke(builder)
            
            result.success(mapOf("success" to true, "message" to "NearPay SDK initialized via reflection"))
        } catch (e: Exception) {
            Log.e("NearPay", "Initialization error: ${e.message}")
            e.printStackTrace()
            result.error("INIT_ERROR", e.message, null)
        }
    }

    private fun jwtLogin(call: MethodCall, result: MethodChannel.Result) {
        val jwt = call.argument<String>("jwt")
        if (jwt == null || nearPay == null) {
            result.error("ERROR", "JWT null or SDK not initialized", null)
            return
        }

        try {
            val authDataClass = try {
                Class.forName("io.nearpay.sdk.data.models.AuthenticationData")
            } catch (e: Exception) {
                Class.forName("io.nearpay.terminalsdk.data.models.AuthenticationData")
            }
            
            val jwtClass = authDataClass.classes.find { it.simpleName == "Jwt" }
                ?: Class.forName("${authDataClass.name}\$Jwt")
            
            val authInstance = jwtClass.getConstructor(String::class.java).newInstance(jwt)

            val loginMethod = nearPay!!.javaClass.methods.find { it.name == "login" && it.parameterCount == 2 }
            
            loginMethod?.invoke(nearPay, authInstance, object : Function1<Any, Unit> {
                override fun invoke(loginResult: Any) {
                    mainScope.launch {
                        try {
                            val isSuccess = loginResult.javaClass.getMethod("isSuccess").invoke(loginResult) as Boolean
                            if (isSuccess) {
                                val user = loginResult.javaClass.getMethod("getOrNull").invoke(loginResult)
                                val userId = user?.javaClass?.methods?.find { it.name == "getId" }?.invoke(user)
                                    ?: user?.javaClass?.fields?.find { it.name == "id" }?.get(user)
                                
                                result.success(mapOf("success" to true, "terminalUUID" to userId?.toString()))
                            } else {
                                val exception = loginResult.javaClass.getMethod("exceptionOrNull").invoke(loginResult) as? Exception
                                result.success(mapOf("success" to false, "message" to exception?.message))
                            }
                        } catch (e: Exception) {
                            result.error("LOGIN_CALLBACK_ERROR", e.message, null)
                        }
                    }
                }
            })
        } catch (e: Exception) {
            result.error("LOGIN_ERROR", e.message, null)
        }
    }

    private fun processPurchase(call: MethodCall, result: MethodChannel.Result) {
        val amount = call.argument<Int>("amount")
        val customerReferenceNumber = call.argument<String>("customerReferenceNumber") ?: ""
        
        if (amount == null || nearPay == null) {
            result.error("ERROR", "Amount null or SDK not initialized", null)
            return
        }

        try {
            // Find the correct purchase method and listener interface
            val purchaseMethod = nearPay!!.javaClass.methods.find { it.name == "purchase" }
            val listenerInterface = purchaseMethod?.parameterTypes?.find { it.isInterface }

            if (purchaseMethod != null && listenerInterface != null) {
                val proxyListener = java.lang.reflect.Proxy.newProxyInstance(
                    listenerInterface.classLoader,
                    arrayOf(listenerInterface)
                ) { proxy, method, args ->
                    when (method.name) {
                        "onPaymentApproved" -> {
                            val paymentResult = args[0]
                            val transaction = paymentResult.javaClass.getMethod("getTransaction").invoke(paymentResult)
                            sendEventToFlutter("onTransactionCompleted", mapOf(
                                "transactionId" to transaction?.javaClass?.methods?.find { it.name == "getId" }?.invoke(transaction),
                                "status" to "approved",
                                "isApproved" to true,
                                "amount" to amount.toDouble() / 100.0,
                                "timestamp" to System.currentTimeMillis()
                            ))
                            null
                        }
                        "onPaymentDeclined" -> {
                            sendEventToFlutter("onTransactionCompleted", mapOf(
                                "status" to "declined",
                                "isApproved" to false
                            ))
                            null
                        }
                        "onPaymentError" -> {
                            val error = args[0]
                            val msg = error.javaClass.getMethod("getMessage").invoke(error)
                            sendEventToFlutter("onTransactionFailure", mapOf("message" to msg))
                            null
                        }
                        else -> null
                    }
                }

                // Call purchase dynamically
                // purchase(amount: Long, customerReferenceNumber: String, enableReversal: Boolean, finishTimeOut: Long, listener: OnPaymentListener)
                val params = arrayOf<Any?>(amount.toLong(), customerReferenceNumber, true, 60000L, proxyListener)
                purchaseMethod.invoke(nearPay, *params)
                
                result.success(mapOf("success" to true, "intentUuid" to UUID.randomUUID().toString()))
            }
        } catch (e: Exception) {
            result.error("PURCHASE_ERROR", e.message, null)
        }
    }

    private fun checkPermissions(result: MethodChannel.Result) {
        result.success(mapOf("success" to true))
    }

    private fun isNfcEnabled(result: MethodChannel.Result) {
        try {
            val nfcAdapter = android.nfc.NfcAdapter.getDefaultAdapter(this)
            result.success(mapOf("isEnabled" to (nfcAdapter?.isEnabled ?: false)))
        } catch (e: Exception) {
            result.error("NFC_ERROR", e.message, null)
        }
    }

    private fun sendEventToFlutter(eventName: String, data: Map<String, Any?>?) {
        mainScope.launch {
            flutterEngine?.dartExecutor?.binaryMessenger?.let {
                MethodChannel(it, CHANNEL).invokeMethod("onNearPayEvent", mapOf("event" to eventName, "data" to data))
            }
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        mainScope.cancel()
    }
}
