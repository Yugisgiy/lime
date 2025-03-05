package android;

import lime._internal.backend.android.JNICache;
import android.Permissions;
import haxe.io.Path;
import lime.app.Event;
import lime.math.Rectangle;
import lime.utils.Log;
import lime.system.JNI;
#if sys
import sys.io.Process;
#end

/**
 * A utility class for interacting with native Android functionality via JNI.
 */
#if android
#if !lime_debug
@:fileXml('tags="haxe,release"')
@:noDebug
#end
class Tools
{
	/**
	 * Prompt the user to install a specific APK file.
	 *
	 * @param path The absolute path to the APK file.
	 */
	public static function installPackage(path:String):Void
	{
		if (!JNICache.createStaticMethod('org/haxe/extension/Tools', 'installPackage', '(Ljava/lang/String;)Z')(path))
			Log.warn('"REQUEST_INSTALL_PACKAGES" permission and "Install apps from external sources" setting must be granted to this app in order to install a '
				+ Path.extension(path).toUpperCase()
				+ ' file.');
	}

	/**
	 * Adds the security flag to the application's window.
	 */
	public static inline function enableAppSecure():Void
	{
		JNICache.createStaticMethod('org/haxe/extension/Tools', 'enableAppSecure', '()V')();
	}

	/**
	 * Clears the security flag from the application's window.
	 */
	public static inline function disableAppSecure():Void
	{
		JNICache.createStaticMethod('org/haxe/extension/Tools', 'disableAppSecure', '()V')();
	}

	/**
	 * Launches an application by its package name.
	 *
	 * @param packageName The package name of the application to launch.
	 * @param requestCode The request code to pass along with the launch request.
	 */
	public static inline function launchPackage(packageName:String, requestCode:Int = 1):Void
	{
		JNICache.createStaticMethod('org/haxe/extension/Tools', 'launchPackage', '(Ljava/lang/String;I)V')(packageName, requestCode);
	}

	/**
	 * Shows an alert dialog with optional positive and negative buttons.
	 *
	 * @param title The title of the alert dialog.
	 * @param message The message content of the alert dialog.
	 * @param positiveButton Optional data for the positive button.
	 * @param negativeButton Optional data for the negative button.
	 */
	public static function showAlertDialog(title:String, message:String, ?positiveButton:ButtonData, ?negativeButton:ButtonData):Void
	{
		if (positiveButton == null)
			positiveButton = {name: null, func: null};

		if (negativeButton == null)
			negativeButton = {name: null, func: null};

		JNICache.createStaticMethod('org/haxe/extension/Tools', 'showAlertDialog',
			'(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Lorg/haxe/lime/HaxeObject;Ljava/lang/String;Lorg/haxe/lime/HaxeObject;)V')(title, message,
				positiveButton.name, new ButtonListener(positiveButton.func), negativeButton.name, new ButtonListener(negativeButton.func));
	}

	/**
	 * Checks if the device is rooted.
	 *
	 * @return `true` if the device is rooted; `false` otherwise.
	 */
	public static function isRooted():Bool
	{
		#if sys
		final process:Process = new Process('su');

		final exitCode:Null<Int> = process.exitCode(true);

		return exitCode != null && exitCode != 255;
		#else
		return false;
		#end
	}

	/**
	 * Checks if the device has Dolby Atmos support.
	 *
	 * @return `true` if the device has Dolby Atmos support; `false` otherwise.
	 */
	public static inline function isDolbyAtmos():Bool
	{
		return JNICache.createStaticMethod('org/haxe/extension/Tools', 'isDolbyAtmos', '()Z')();
	}

	/**
	 * Shows a minimal notification with a title and message.
	 *
	 * @param title The title of the notification.
	 * @param message The message content of the notification.
	 * @param channelID Optional ID of the notification channel.
	 * @param channelName Optional name of the notification channel.
	 * @param ID Optional unique ID for the notification.
	 */
	public static inline function showNotification(title:String, message:String, ?channelID:String = 'unknown_channel',
			?channelName:String = 'Unknown Channel', ?ID:Int = 1):Void
	{
		JNICache.createStaticMethod('org/haxe/extension/Tools', 'showNotification',
			'(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;I)V')(title, message, channelID, channelName, ID);
	}

	/**
	 * Retrieves the dimensions of display cutouts (notches) as an array of rectangles.
	 *
	 * On devices with Android 9.0 (Pie) or higher, this function returns the areas of the screen 
	 * occupied by display cutouts, such as notches or camera holes. Each cutout is represented 
	 * by a `lime.math.Rectangle` object indicating its position and size.
	 *
	 * @return An array of `lime.math.Rectangle` objects representing the cutout areas. If there 
	 *         are no cutouts or if the device does not support cutouts, an empty array is returned.
	 */
	public static function getCutoutDimensions():Array<Rectangle>
	{
		final cutoutRectangles:Array<Dynamic> = JNICache.createStaticMethod('org/haxe/extension/Tools', 'getCutoutDimensions', '()[Landroid/graphics/Rect;')();

		if (cutoutRectangles == null || cutoutRectangles.length == 0)
			return [];

		final rectangles:Array<Rectangle> = [];

		for (rectangle in cutoutRectangles)
		{
			if (rectangle == null)
				continue;

			final top:Int = JNICache.createMemberField('android/graphics/Rect', 'top', 'I').get(rectangle);
			final left:Int = JNICache.createMemberField('android/graphics/Rect', 'left', 'I').get(rectangle);
			final right:Int = JNICache.createMemberField('android/graphics/Rect', 'right', 'I').get(rectangle);
			final bottom:Int = JNICache.createMemberField('android/graphics/Rect', 'bottom', 'I').get(rectangle);

			rectangles.push(new Rectangle(left, top, right - left, bottom - top));
		}

		return rectangles;
	}
	
	/**
	 * Sets the activity's title.
	 *
	 * @param title The title to set for the activity.
	 * @return `true` if the title was successfully set; `false` otherwise.
	 */
	public static inline function setActivityTitle(title:String):Bool
	{
		return JNICache.createStaticMethod('org/libsdl/app/SDLActivity', 'setActivityTitle', '(Ljava/lang/String;)Z')(title);
	}

	/**
	 * Minimizes the application's window.
	 */
	public static inline function minimizeWindow():Void
	{
		JNICache.createStaticMethod('org/libsdl/app/SDLActivity', 'minimizeWindow', '()V')();
	}

	/**
	 * Checks if the device is running Android TV.
	 *
	 * @return `true` if the device is running Android TV; `false` otherwise.
	 */
	public static inline function isAndroidTV():Bool
	{
		return JNICache.createStaticMethod('org/libsdl/app/SDLActivity', 'isAndroidTV', '()Z')();
	}

	/**
	 * Checks if the device is a tablet.
	 *
	 * @return `true` if the device is a tablet; `false` otherwise.
	 */
	public static inline function isTablet():Bool
	{
		return JNICache.createStaticMethod('org/libsdl/app/SDLActivity', 'isTablet', '()Z')();
	}

	/**
	 * Checks if the device is a Chromebook.
	 *
	 * @return `true` if the device is a Chromebook; `false` otherwise.
	 */
	public static inline function isChromebook():Bool
	{
		return JNICache.createStaticMethod('org/libsdl/app/SDLActivity', 'isChromebook', '()Z')();
	}

	/**
	 * Checks if the device is running in DeX Mode.
	 *
	 * @return `true` if the device is running in DeX Mode; `false` otherwise.
	 */
	public static inline function isDeXMode():Bool
	{
		return JNICache.createStaticMethod('org/libsdl/app/SDLActivity', 'isDeXMode', '()Z')();
	}
}

/**
 * Data structure for defining button properties in an alert dialog.
 */
@:noCompletion
private typedef ButtonData =
{
	name:String,
	// The name or label of the button.
	func:Void->Void
	// The callback function to execute when the button is clicked.
}

/**
 * Listener class for handling button click events in an alert dialog.
 */
@:noCompletion
#if !lime_debug
@:fileXml('tags="haxe,release"')
@:noDebug
#end
private class ButtonListener #if android implements JNISafety #end
{
	private var onClickEvent:Event<Void->Void> = new Event<Void->Void>();

	/**
	 * Creates a new button listener with a specified callback function.
	 *
	 * @param clickCallback The function to execute when the button is clicked.
	 */
	public function new(clickCallback:Void->Void):Void
	{
		if (clickCallback != null)
			onClickEvent.add(clickCallback);
	}

	@:runOnMainThread
	public function onClick():Void
	{
		onClickEvent.dispatch();
	}
}
#end
