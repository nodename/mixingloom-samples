package patcher
{
import flash.events.Event;
import flash.events.TimerEvent;
import flash.net.URLLoader;
import flash.net.URLLoaderDataFormat;
import flash.net.URLRequest;
import flash.utils.ByteArray;
import flash.utils.ByteArray;
import flash.utils.ByteArray;
import flash.utils.Endian;

import org.as3commons.bytecode.abc.AbcFile;
import org.as3commons.bytecode.abc.ClassInfo;
import org.as3commons.bytecode.abc.InstanceInfo;
import org.as3commons.bytecode.abc.LNamespace;
import org.as3commons.bytecode.abc.MethodInfo;
import org.as3commons.bytecode.abc.Op;
import org.as3commons.bytecode.abc.QualifiedName;
import org.as3commons.bytecode.abc.enum.Opcode;
import org.as3commons.bytecode.io.AbcSerializer;

import org.mixingloom.SwfContext;
import org.mixingloom.SwfTag;
import org.mixingloom.invocation.InvocationType;
import org.mixingloom.patcher.AbstractPatcher;

import org.as3commons.bytecode.io.AbcDeserializer;

public class SampleXMLPatcher extends AbstractPatcher {

    public var url:String;

    private var swfContext:SwfContext;

    public function SampleXMLPatcher(url:String) {
        this.url = url;
    }

    private function handleTimerComplete( event:TimerEvent ):void {
        invokeCallBack();
    }

    override public function apply( invocationType:InvocationType, swfContext:SwfContext ):void {
        if (invocationType.type == InvocationType.FRAME2) {

            // I don't like doing it this way, but it's a demo
            this.swfContext = swfContext;

            var urlLoader:URLLoader = new URLLoader();
            urlLoader.dataFormat = URLLoaderDataFormat.TEXT;
            urlLoader.addEventListener(Event.COMPLETE, handleXMLLoad);
            urlLoader.load(new URLRequest(url));
        }
        else {
            invokeCallBack();
        }
    }

    private function handleXMLLoad(event:Event):void {
        var xmlData:XML = new XML((event.currentTarget as URLLoader).data as String);

        var swfTagName:String = xmlData.interceptor.swfTags.swfTag; // doesn't handle multiple
        var classes:String = xmlData.interceptor.classes; // doesn't handle multiple
        var methods:String = xmlData.interceptor.methods; // doesn't handle multiple
        var methodEntryInvokerClassName:String = xmlData.interceptor.methodEntryInvoker.className;
        var methodEntryInvokerMethodName:String = xmlData.interceptor.methodEntryInvoker.methodName;

        var methodEntryInvokerClassQName:QualifiedName = new QualifiedName(methodEntryInvokerClassName, LNamespace.PUBLIC);
        var methodEntryInvokerMethodQName:QualifiedName = new QualifiedName(methodEntryInvokerMethodName, LNamespace.PUBLIC);

        for each (var swfTag:SwfTag in swfContext.swfTags) {
            if (swfTag.name == swfTagName) {

                // skip the flags
                swfTag.tagBody.position = 4;

                var abcStartLocation:uint = 4;
                while (swfTag.tagBody.readByte() != 0)
                {
                    abcStartLocation++;
                }
                abcStartLocation++; // skip the string byte terminator

                swfTag.tagBody.position = 0;

                var abcDeserializer:AbcDeserializer = new AbcDeserializer(swfTag.tagBody);

                var abcFile:AbcFile = abcDeserializer.deserialize(abcStartLocation);

                // need to locate the method we are going to call in the constant pool


                if (classes == "*") {
                    for each (var instanceInfo:InstanceInfo in abcFile.instanceInfo) {
                        if (methods == "*") {
                            for each (var methodInfo:MethodInfo in instanceInfo.methodInfo) {
                                var startIndex:uint = 0;
                                for each (var op:Op in methodInfo.methodBody.opcodes) {
                                    startIndex++;
                                    if (op.opcode === Opcode.pushscope) {
                                        break;
                                    }
                                }

                                var findOp:Op = new Op(Opcode.findpropstrict, [methodEntryInvokerClassQName]);
                                var getOp:Op = new Op(Opcode.getproperty, [methodEntryInvokerClassQName]);
                                var callOp:Op = new Op(Opcode.callproperty, [methodEntryInvokerMethodQName, 0]);

                                methodInfo.methodBody.opcodes.splice(startIndex, 0, findOp, getOp, callOp, new Op(Opcode.pop));
                            }
                        }
                    }
                }

                var abcSerializer:AbcSerializer = new AbcSerializer();
                var modifiedBytes:ByteArray = new ByteArray();
                modifiedBytes.writeBytes(swfTag.tagBody, 0, abcStartLocation);
                modifiedBytes.writeBytes(abcSerializer.serializeAbcFile(abcFile));

                swfTag.tagBody = modifiedBytes;

                // update the recordHeader
                swfTag.recordHeader = new ByteArray();
                swfTag.recordHeader.endian = Endian.LITTLE_ENDIAN;
                swfTag.recordHeader.writeByte(0xbf);
                swfTag.recordHeader.writeByte(0x14);
                swfTag.recordHeader.writeInt(swfTag.tagBody.length);

                swfTag.modified = true;
            }
        }

        invokeCallBack();
    }
}
}